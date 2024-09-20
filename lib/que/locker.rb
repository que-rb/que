# frozen_string_literal: true

# The Locker class encapsulates a thread that is listening/polling for new
# jobs in the DB, locking them, passing their primary keys to workers, then
# cleaning up by unlocking them once the workers are done.

require 'set'

module Que
  class << self
    attr_accessor :locker
  end

  Listener::MESSAGE_FORMATS[:job_available] =
    {
      queue:    String,
      id:       Integer,
      run_at:   TIME_REGEX,
      priority: Integer,
    }

  SQL[:clean_lockers] =
    %{
      DELETE FROM public.que_lockers
      WHERE pid = pg_backend_pid()
      OR NOT EXISTS (SELECT 1 FROM pg_stat_activity WHERE pid = public.que_lockers.pid)
    }

  SQL[:register_locker] =
    %{
      INSERT INTO public.que_lockers (pid, worker_count, worker_priorities, ruby_pid, ruby_hostname, listening, queues, job_schema_version)
      VALUES (pg_backend_pid(), $1::integer, $2::integer[], $3::integer, $4::text, $5::boolean, $6::text[], $7::integer)
    }

  class Locker
    attr_reader :thread, :workers, :job_buffer, :locks, :queues, :poll_interval, :poll_interval_variance

    MESSAGE_RESOLVERS = {}
    RESULT_RESOLVERS  = {}

    MESSAGE_RESOLVERS[:job_available] =
      -> (messages) {
        metajobs = messages.map { |key| Metajob.new(key) }
        push_jobs(lock_jobs(job_buffer.accept?(metajobs)))
      }

    RESULT_RESOLVERS[:job_finished] =
      -> (messages) { finish_jobs(messages.map{|m| m.fetch(:metajob)}) }

    DEFAULT_POLL_INTERVAL          = 5.0
    DEFAULT_POLL_INTERVAL_VARIANCE = 0.0
    DEFAULT_WAIT_PERIOD            = 50
    DEFAULT_MAXIMUM_BUFFER_SIZE    = 8
    DEFAULT_WORKER_PRIORITIES      = [10, 30, 50, nil, nil, nil].freeze

    def initialize(
      queues:                 [Que.default_queue],
      connection_url:         nil,
      listen:                 true,
      poll:                   true,
      poll_interval:          DEFAULT_POLL_INTERVAL,
      poll_interval_variance: DEFAULT_POLL_INTERVAL_VARIANCE,
      wait_period:            DEFAULT_WAIT_PERIOD,
      maximum_buffer_size:    DEFAULT_MAXIMUM_BUFFER_SIZE,
      worker_priorities:      DEFAULT_WORKER_PRIORITIES,
      on_worker_start:        nil,
      pidfile:                nil
    )

      # Sanity-check all our arguments, since some users may instantiate Locker
      # directly.
      Que.assert [TrueClass, FalseClass], listen
      Que.assert [TrueClass, FalseClass], poll

      Que.assert Numeric, poll_interval
      Que.assert Numeric, poll_interval_variance
      Que.assert Numeric, wait_period

      Que.assert Array, worker_priorities
      worker_priorities.each { |p| Que.assert([Integer, NilClass], p) }

      # We assign this globally because we only ever expect one locker to be
      # created per worker process. This can be used by middleware or external
      # code to access the locker during runtime.
      Que.locker = self

      # We use a JobBuffer to track jobs and pass them to workers, and a
      # ResultQueue to receive messages from workers.
      @job_buffer = JobBuffer.new(
        maximum_size: maximum_buffer_size,
        priorities:   worker_priorities.uniq,
      )

      @result_queue = ResultQueue.new

      @stop = false

      Que.internal_log :locker_instantiate, self do
        {
          queues:                 queues,
          listen:                 listen,
          poll:                   poll,
          poll_interval:          poll_interval,
          poll_interval_variance: poll_interval_variance,
          wait_period:            wait_period,
          maximum_buffer_size:    maximum_buffer_size,
          worker_priorities:      worker_priorities,
        }
      end

      # Local cache of which advisory locks are held by this connection.
      @locks = Set.new

      @poll_interval = poll_interval
      @poll_interval_variance = poll_interval_variance

      if queues.is_a?(Hash)
        @queue_names = queues.keys
        @queues = queues.transform_values do |interval|
          interval || poll_interval
        end
      else
        @queue_names = queues
        @queues = queues.map do |queue_name|
          [queue_name, poll_interval]
        end.to_h
      end

      @wait_period = wait_period.to_f / 1000 # Milliseconds to seconds.

      @workers =
        worker_priorities.map do |priority|
          Worker.new(
            priority:       priority,
            job_buffer:     @job_buffer,
            result_queue:   @result_queue,
            start_callback: on_worker_start,
          )
        end

      # To prevent race conditions, let every worker get into a ready state
      # before starting up the locker thread.
      loop do
        break if job_buffer.waiting_count == workers.count
        sleep 0.001
      end

      # If we weren't passed a specific connection_url, borrow a connection from
      # the pool and derive the connection string from it.
      connection_args =
        if connection_url
          uri = URI.parse(connection_url)

          opts =
            {
              host:     uri.host,
              user:     uri.user,
              password: uri.password,
              port:     uri.port || 5432,
              dbname:   uri.path[1..-1],
            }

          if uri.query
            opts.merge!(Hash[uri.query.split("&").map{|s| s.split('=')}.map{|a,b| [a.to_sym, b]}])
          end

          opts
        else
          Que.pool.checkout do |conn|
            c = conn.wrapped_connection

            {
              host:     c.host,
              user:     c.user,
              password: c.pass,
              port:     c.port,
              dbname:   c.db,
            }
          end
        end

      @connection = Que::Connection.wrap(PG::Connection.open(connection_args))

      @thread =
        Thread.new do
          # An error causing this thread to exit is a bug in Que, which we want
          # to know about ASAP, so propagate the error if it happens.
          Thread.current.abort_on_exception = true

          # Give this thread priority, so it can promptly respond to NOTIFYs.
          Thread.current.priority = 1

          begin
            unless connection_args.has_key?(:application_name)
              @connection.execute(
                "SELECT set_config('application_name', $1, false)",
                ["Que Locker: #{@connection.backend_pid}"]
              )
            end

            Poller.setup(@connection)

            @listener =
              if listen
                Listener.new(connection: @connection)
              end

            @pollers =
              if poll
                @queues.map do |queue_name, interval|
                  Poller.new(
                    connection:             @connection,
                    queue:                  queue_name,
                    poll_interval:          interval,
                    poll_interval_variance: poll_interval_variance,
                  )
                end
              end

            work_loop
          ensure
            @connection.wrapped_connection.close
          end
        end

      @pidfile = pidfile
      at_exit { delete_pid }
      write_pid
    end

    def stop!
      stop
      wait_for_stop
      delete_pid
    end

    def stop
      @job_buffer.stop
      @stop = true
    end

    def stopping?
      @stop
    end

    def wait_for_stop
      @thread.join
    end

    private

    attr_reader :connection, :pollers

    def work_loop
      Que.log(
        level: :debug,
        event: :locker_start,
        queues: @queue_names,
      )

      Que.internal_log :locker_start, self do
        {
          backend_pid: connection.backend_pid,
          worker_priorities: workers.map(&:priority),
          pollers: pollers && pollers.map { |p| [p.queue, p.poll_interval] }
        }
      end

      begin
        @listener.listen if @listener

        startup

        {} while cycle

        Que.log(
          level: :debug,
          event: :locker_stop,
        )

        shutdown
      ensure
        connection.execute :clean_lockers

        @listener.unlisten if @listener
      end
    end

    def startup
      # A previous locker that didn't exit cleanly may have left behind
      # a bad locker record, so clean up before registering.
      connection.execute :clean_lockers
      connection.execute :register_locker, [
        @workers.count,
        "{#{@workers.map(&:priority).map{|p| p || 'NULL'}.join(',')}}",
        Process.pid,
        CURRENT_HOSTNAME,
        !!@listener,
        "{\"#{@queue_names.join('","')}\"}",
        Que.job_schema_version,
      ]
    end

    def cycle
      # Poll at the start of a cycle, so that when the worker starts up we can
      # load up the queue with jobs immediately.
      poll

      # If we got the stop call while we were polling, break before going to
      # sleep.
      return if @stop

      # The main sleeping part of the cycle. If this is a listening locker, this
      # is where we wait for notifications.
      wait

      # Manage any job output we got while we were sleeping.
      handle_results

      # If we haven't gotten the stop signal, cycle again.
      !@stop
    end

    def shutdown
      unlock_jobs(@job_buffer.clear)
      wait_for_shutdown
      handle_results
    end

    def wait_for_shutdown
      @workers.each(&:wait_until_stopped)
    end

    def poll
      # Only poll when there are pollers to use (that is, when polling is
      # enabled).
      return unless pollers

      # Figure out what job priorities we have to fill.
      priorities = job_buffer.available_priorities

      # Only poll when there are workers ready for jobs.
      return if priorities.empty?

      all_metajobs = []

      pollers.each do |poller|
        Que.internal_log(:locker_polling, self) {
          {
            priorities: priorities,
            held_locks: @locks.to_a,
            queue: poller.queue,
          }
        }

        if metajobs = poller.poll(priorities: priorities, held_locks: @locks)
          metajobs.sort!
          all_metajobs.concat(metajobs)

          # Update the desired priorities list to take the priorities that we
          # just retrieved into account.
          metajobs.each do |metajob|
            job_priority = metajob.job.fetch(:priority)

            priorities.each do |priority, count|
              if job_priority <= priority
                new_priority = count - 1

                if new_priority <= 0
                  priorities.delete(priority)
                else
                  priorities[priority] = new_priority
                end

                break
              end
            end
          end

          break if priorities.empty?
        end
      end

      all_metajobs.each { |metajob| mark_id_as_locked(metajob.id) }
      push_jobs(all_metajobs)
    end

    def wait
      if l = @listener
        l.wait_for_grouped_messages(@wait_period).each do |type, messages|
          if resolver = MESSAGE_RESOLVERS[type]
            instance_exec messages, &resolver
          else
            raise Error, "Unexpected message type: #{type.inspect}"
          end
        end
      else
        sleep(@wait_period)
      end
    end

    def handle_results
      messages_by_type =
        @result_queue.clear.group_by{|r| r.fetch(:message_type)}

      messages_by_type.each do |type, messages|
        if resolver = RESULT_RESOLVERS[type]
          instance_exec messages, &resolver
        else
          raise Error, "Unexpected result type: #{type.inspect}"
        end
      end
    end

    def lock_jobs(metajobs)
      metajobs.reject! { |m| @locks.include?(m.id) }
      return metajobs if metajobs.empty?

      ids = metajobs.map { |m| m.id.to_i }

      Que.internal_log :locker_locking, self do
        {
          backend_pid: connection.backend_pid,
          ids:         ids,
        }
      end

      materalize_cte = connection.server_version >= 12_00_00

      jobs =
        connection.execute \
          <<-SQL
            WITH jobs AS #{materalize_cte ? 'MATERIALIZED' : ''} (SELECT * FROM que_jobs WHERE id IN (#{ids.join(', ')}))
            SELECT * FROM jobs WHERE pg_try_advisory_lock(id)
          SQL

      jobs_by_id = {}

      jobs.each do |job|
        id = job.fetch(:id)
        mark_id_as_locked(id)
        jobs_by_id[id] = job
      end

      metajobs.keep_if do |metajob|
        if job = jobs_by_id[metajob.id]
          metajob.set_job(job)
          true
        else
          false
        end
      end
    end

    def push_jobs(metajobs)
      return if metajobs.empty?

      # First check that the jobs are all still visible/available in the DB.
      ids = metajobs.map(&:id)

      verified_ids =
        connection.execute(
          <<-SQL
            SELECT id
            FROM public.que_jobs
            WHERE finished_at IS NULL
              AND expired_at IS NULL
              AND id IN (#{ids.join(', ')})
          SQL
        ).map{|h| h[:id]}.to_set

      good, bad = metajobs.partition{|mj| verified_ids.include?(mj.id)}

      # Need to unlock any low-importance jobs the new ones may displace.
      if displaced = @job_buffer.push(*good)
        bad.concat(displaced)
      end

      unlock_jobs(bad)
    end

    def finish_jobs(metajobs)
      unlock_jobs(metajobs)
    end

    def unlock_jobs(metajobs)
      return if metajobs.empty?

      # Unclear how untrusted input would get passed to this method, but since
      # we need string interpolation here, make sure we only have integers.
      ids = metajobs.map { |job| job.id.to_i }

      Que.internal_log :locker_unlocking, self do
        {
          backend_pid: connection.backend_pid,
          ids:         ids,
        }
      end

      values = ids.join('), (')

      results =
        connection.execute \
          "SELECT pg_advisory_unlock(v.i) FROM (VALUES (#{values})) v (i)"

      results.each do |result|
        Que.assert(result.fetch(:pg_advisory_unlock)) do
          [
            "Tried to unlock a job we hadn't locked!",
            results.inspect,
            ids.inspect,
          ].join(' ')
        end
      end

      ids.each do |id|
        Que.assert(@locks.delete?(id)) do
          "Tried to remove a local lock that didn't exist!: #{id}"
        end
      end
    end

    def mark_id_as_locked(id)
      Que.assert(@locks.add?(id)) do
        "Tried to lock a job that was already locked: #{id}"
      end
    end

    def write_pid
      return unless @pidfile

      File.open(@pidfile, "w+") do |f|
        f.write(Process.pid.to_s)
      end
    end

    def delete_pid
      return unless @pidfile

      File.delete(@pidfile) if File.exist?(@pidfile)
    end
  end
end
