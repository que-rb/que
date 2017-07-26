# frozen_string_literal: true

# The Locker class encapsulates a thread that is listening/polling for new
# jobs in the DB, locking them, passing their primary keys to workers, then
# cleaning up by unlocking them once the workers are done.

require 'set'

module Que
  Listener::MESSAGE_CALLBACKS[:new_job] = -> (message) {
    message[:run_at] = Time.parse(message.fetch(:run_at))
  }

  Listener::MESSAGE_FORMATS[:new_job] =
    {
      queue:    String,
      id:       Integer,
      run_at:   Time,
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
    attr_reader :thread, :workers, :job_queue, :locks, :pollers, :connection

    MESSAGE_RESOLVERS = Utils::Registrar.new
    RESULT_RESOLVERS  = Utils::Registrar.new

    MESSAGE_RESOLVERS[:new_job] =
      -> (messages) {
        # TODO: Check for acceptance in bulk, attempt locking in bulk, push jobs
        # in bulk.
        messages.each do |message|
          if @job_queue.accept?(message) && lock_job?(message.fetch(:id))
            push_jobs([message])
          end
        end
      }

    RESULT_RESOLVERS[:job_finished] =
      -> (messages) {
        unlock_jobs(messages.map{|m| m.fetch(:id)})
      }

    DEFAULT_POLL_INTERVAL      = 5.0
    DEFAULT_WAIT_PERIOD        = 50
    DEFAULT_MINIMUM_QUEUE_SIZE = 2
    DEFAULT_MAXIMUM_QUEUE_SIZE = 8
    DEFAULT_WORKER_COUNT       = 6
    DEFAULT_WORKER_PRIORITIES  = [10, 30, 50].freeze

    def initialize(
      queues:             [Que.default_queue],
      connection:         nil,
      listen:             true,
      poll:               true,
      poll_interval:      DEFAULT_POLL_INTERVAL,
      wait_period:        DEFAULT_WAIT_PERIOD,
      maximum_queue_size: DEFAULT_MAXIMUM_QUEUE_SIZE,
      minimum_queue_size: DEFAULT_MINIMUM_QUEUE_SIZE,
      worker_count:       DEFAULT_WORKER_COUNT,
      worker_priorities:  DEFAULT_WORKER_PRIORITIES,
      on_worker_start:    nil
    )

      # Sanity-check all our arguments, since some users may instantiate Locker
      # directly.
      Que.assert [TrueClass, FalseClass], listen
      Que.assert [TrueClass, FalseClass], poll

      Que.assert Numeric, poll_interval
      Que.assert Numeric, wait_period
      Que.assert Integer, maximum_queue_size
      Que.assert Integer, minimum_queue_size
      Que.assert Integer, worker_count

      Que.assert Array, worker_priorities
      worker_priorities.each { |p| Que.assert(Integer, p) }

      Que.assert(minimum_queue_size <= maximum_queue_size) do
        "minimum_queue_size (#{minimum_queue_size}) is " \
          "greater than the maximum_queue_size (#{maximum_queue_size})!"
      end

      Que.internal_log :locker_instantiate, self do
        {
          queues:             queues,
          listen:             listen,
          poll:               poll,
          poll_interval:      poll_interval,
          wait_period:        wait_period,
          maximum_queue_size: maximum_queue_size,
          minimum_queue_size: minimum_queue_size,
          worker_count:       worker_count,
          worker_priorities:  worker_priorities,
        }
      end

      # Local cache of which advisory locks are held by this connection.
      @locks = Set.new

      @queue_names        = queues.is_a?(Hash) ? queues.keys : queues
      @wait_period        = wait_period.to_f / 1000 # Milliseconds to seconds.
      @minimum_queue_size = minimum_queue_size

      # We use a JobQueue to track sorted identifiers (priority, run_at, id) of
      # locked jobs and pass them to workers, and a ResultQueue to receive
      # messages from workers.
      @job_queue    = JobQueue.new(maximum_size: maximum_queue_size)
      @result_queue = ResultQueue.new

      # If the worker_count exceeds the array of priorities it'll result in
      # extra workers that will work jobs of any priority. For example, the
      # default worker_count of 6 and the default worker priorities of [10, 30,
      # 50] will result in three workers that only work jobs that meet those
      # priorities, and three workers that will work any job.
      @workers =
        worker_count.times.zip(worker_priorities).map do |_, priority|
          Worker.new(
            priority:       priority,
            job_queue:      @job_queue,
            result_queue:   @result_queue,
            start_callback: on_worker_start,
          )
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
            @connection = connection

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
          end
        end
    end

    def stop!
      stop; wait_for_stop
    end

    def stop
      @stop = true
    end

    def wait_for_stop
      @thread.join
    end

    private

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
        execute :clean_lockers
        execute :register_locker, [
          @workers.count,
          "{#{@workers.map(&:priority).map{|p| p || 'NULL'}.join(',')}}",
          Process.pid,
          CURRENT_HOSTNAME,
          !!@listener,
          "{\"#{@queue_names.join('","')}\"}",
        ]

        loop do
          poll
          break if @stop

          wait
          break if @stop

          handle_results
        end

        Que.log(
          level: :debug,
          event: :locker_stop,
        )

        unlock_jobs(@job_queue.clear)

        @job_queue.stop
        @workers.each(&:wait_until_stopped)

        handle_results
      ensure
        execute :clean_lockers

        @listener.unlisten if @listener
      end
    end

    extend Forwardable
    def_delegators :connection, :execute

    def poll
      return unless pollers
      return unless @job_queue.size < @minimum_queue_size

      space = @job_queue.space

      Que.internal_log(:locker_polling, self) { {space: space} }

      pollers.each do |poller|
        break if space <= 0

        if sort_keys = poller.poll(space, held_locks: @locks)
          sort_keys.each do |sort_key|
            mark_id_as_locked(sort_key.fetch(:id))
          end

          push_jobs(sort_keys)
          space -= sort_keys.length
        end
      end
    end

    def wait
      if @listener.nil?
        sleep(@wait_period)
        return
      end

      @listener.wait_for_messages(@wait_period).each do |type, messages|
        if resolver = MESSAGE_RESOLVERS[type]
          instance_exec messages, &resolver
        else
          # TODO: Unexpected type - log something? Ignore it?
        end
      end
    end

    def lock_job?(id)
      return false if @locks.include?(id)
      return false unless try_advisory_lock(id)

      mark_id_as_locked(id)
      true
    end

    def try_advisory_lock(id)
      r = execute("SELECT pg_try_advisory_lock($1) AS l", [id]).first.fetch(:l)

      Que.internal_log :locker_attempted_lock, self do
        {
          backend_pid: connection.backend_pid,
          id:          id,
          result:      r,
        }
      end

      r
    end

    def handle_results
      messages_by_type =
        @result_queue.clear.group_by{|r| r.fetch(:message_type)}

      messages_by_type.each do |type, messages|
        if resolver = RESULT_RESOLVERS[type]
          instance_exec messages, &resolver
        else
          raise Error, "Unexpected result message type: #{type.inspect}"
        end
      end
    end

    def push_jobs(sort_keys)
      # Unlock any low-importance jobs the new ones may displace.
      if ids = @job_queue.push(*sort_keys)
        unlock_jobs(ids)
      end
    end

    def unlock_jobs(ids)
      return if ids.empty?

      # Unclear how untrusted input would get passed to this method, but since
      # we need string interpolation here, make sure we only have integers.
      ids.map!(&:to_i)

      Que.internal_log :locker_unlocking, self do
        {
          # TODO: backend_pid: connection.backend_pid,
          ids: ids,
        }
      end

      values = ids.join('), (')

      results =
        execute "SELECT pg_advisory_unlock(v.i) FROM (VALUES (#{values})) v (i)"

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
