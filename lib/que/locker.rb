# frozen_string_literal: true

# The Locker class encapsulates a thread that is listening/polling for new
# jobs in the DB, locking them, passing their primary keys to workers, then
# cleaning up by unlocking them once the workers are done.

require 'set'

module Que
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
      OR pid NOT IN (SELECT pid FROM pg_stat_activity)
    }

  SQL[:register_locker] =
    %{
      INSERT INTO public.que_lockers
      (
        pid,
        worker_count,
        worker_priorities,
        ruby_pid,
        ruby_hostname,
        listening,
        queues
      )
      VALUES
      (
        pg_backend_pid(),
        $1::integer,
        $2::integer[],
        $3::integer,
        $4::text,
        $5::boolean,
        $6::text[]
      )
    }

  class Locker
    attr_reader :thread, :workers, :job_buffer, :locks

    MESSAGE_RESOLVERS = {}
    RESULT_RESOLVERS  = {}

    MESSAGE_RESOLVERS[:job_available] =
      -> (messages) {
        metajobs = messages.map { |key| Metajob.new(key) }
        push_jobs(lock_jobs(job_buffer.accept?(metajobs)))
      }

    RESULT_RESOLVERS[:job_finished] =
      -> (messages) { finish_jobs(messages.map{|m| m.fetch(:metajob)}) }

    DEFAULT_POLL_INTERVAL       = 5.0
    DEFAULT_WAIT_PERIOD         = 50
    DEFAULT_MINIMUM_BUFFER_SIZE = 2
    DEFAULT_MAXIMUM_BUFFER_SIZE = 8
    DEFAULT_WORKER_COUNT        = 6
    DEFAULT_WORKER_PRIORITIES   = [10, 30, 50].freeze

    def initialize(
      queues:              [Que.default_queue],
      connection:          nil,
      listen:              true,
      poll:                true,
      poll_interval:       DEFAULT_POLL_INTERVAL,
      wait_period:         DEFAULT_WAIT_PERIOD,
      maximum_buffer_size: DEFAULT_MAXIMUM_BUFFER_SIZE,
      minimum_buffer_size: DEFAULT_MINIMUM_BUFFER_SIZE,
      worker_count:        DEFAULT_WORKER_COUNT,
      worker_priorities:   DEFAULT_WORKER_PRIORITIES,
      on_worker_start:     nil
    )

      # Sanity-check all our arguments, since some users may instantiate Locker
      # directly.
      Que.assert [TrueClass, FalseClass], listen
      Que.assert [TrueClass, FalseClass], poll

      Que.assert Numeric, poll_interval
      Que.assert Numeric, wait_period
      Que.assert Integer, worker_count

      Que.assert Array, worker_priorities
      worker_priorities.each { |p| Que.assert(Integer, p) }

      all_worker_priorities = worker_priorities.values_at(0...worker_count)

      # We use a JobBuffer to track jobs and pass them to workers, and a
      # ResultQueue to receive messages from workers.
      @job_buffer = JobBuffer.new(
        maximum_size: maximum_buffer_size,
        minimum_size: minimum_buffer_size,
        priorities:   all_worker_priorities.uniq,
      )

      @result_queue = ResultQueue.new

      Que.internal_log :locker_instantiate, self do
        {
          queues:              queues,
          listen:              listen,
          poll:                poll,
          poll_interval:       poll_interval,
          wait_period:         wait_period,
          maximum_buffer_size: maximum_buffer_size,
          minimum_buffer_size: minimum_buffer_size,
          worker_count:        worker_count,
          worker_priorities:   worker_priorities,
        }
      end

      # Local cache of which advisory locks are held by this connection.
      @locks = Set.new

      @queue_names = queues.is_a?(Hash) ? queues.keys : queues
      @wait_period = wait_period.to_f / 1000 # Milliseconds to seconds.

      # If the worker_count exceeds the array of priorities it'll result in
      # extra workers that will work jobs of any priority. For example, the
      # default worker_count of 6 and the default worker priorities of [10, 30,
      # 50] will result in three workers that only work jobs that meet those
      # priorities, and three workers that will work any job.
      @workers =
        all_worker_priorities.map do |priority|
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

      pool =
        if connection
          # Wrap the given connection in a dummy connection pool.
          ConnectionPool.new { |&block| block.call(connection) }
        else
          Que.pool
        end

      @thread =
        Thread.new do
          # An error causing this thread to exit is a bug in Que, which we want
          # to know about ASAP, so propagate the error if it happens.
          Thread.current.abort_on_exception = true

          # Give this thread priority, so it can promptly respond to NOTIFYs.
          Thread.current.priority = 1

          pool.checkout do |connection|
            original_application_name =
              connection.
              execute("SHOW application_name").
              first.
              fetch(:application_name)

            begin
              @connection = connection

              connection.execute(
                "SELECT set_config('application_name', $1, false)",
                ["Que Locker: #{connection.backend_pid}"]
              )

              Poller.setup(connection)

              if listen
                @listener = Listener.new(connection: connection)
              end

              if poll
                @pollers =
                  queues.map do |queue, interval|
                    Poller.new(
                      connection:    connection,
                      queue:         queue,
                      poll_interval: interval || poll_interval,
                    )
                  end
              end

              work_loop
            ensure
              connection.execute(
                "SELECT set_config('application_name', $1, false)",
                [original_application_name]
              )

              Poller.cleanup(connection)
            end
          end
        end
    end

    def stop!
      stop; wait_for_stop
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
        ]

        {} while cycle

        Que.log(
          level: :debug,
          event: :locker_stop,
        )

        unlock_jobs(@job_buffer.clear)

        @workers.each(&:wait_until_stopped)

        handle_results
      ensure
        connection.execute :clean_lockers

        @listener.unlisten if @listener
      end
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

    def poll
      # Only poll when there are pollers to use (that is, when polling is
      # enabled) and when the local queue has dropped below the configured
      # minimum size.
      return unless pollers && job_buffer.jobs_needed?

      pollers.each do |poller|
        priorities = job_buffer.available_priorities
        break if priorities.empty?

        Que.internal_log(:locker_polling, self) { {priorities: priorities, held_locks: @locks.to_a, queue: poller.queue} }

        if metajobs = poller.poll(priorities: priorities, held_locks: @locks)
          metajobs.each do |metajob|
            mark_id_as_locked(metajob.id)
          end

          push_jobs(metajobs)
        end
      end
    end

    def wait
      if @listener
        @listener.wait_for_grouped_messages(@wait_period).each do |type, messages|
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

      ids = metajobs.map{|m| m.id.to_i}

      Que.internal_log :locker_locking, self do
        {
          backend_pid: connection.backend_pid,
          ids:         ids,
        }
      end

      jobs =
        connection.execute \
          <<-SQL
            WITH jobs AS (
              SELECT * FROM que_jobs WHERE id IN (#{ids.join(', ')})
            )
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

      displaced = @job_buffer.push(*good) || []

      # Unlock any low-importance jobs the new ones may displace.
      if bad.any? || displaced.any?
        unlock_jobs(bad + displaced)
      end
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
  end
end
