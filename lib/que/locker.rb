# frozen_string_literal: true

# The Locker class encapsulates a thread that is listening/polling for new
# jobs in the DB, locking them, passing their primary keys to workers, then
# cleaning up by unlocking them once the workers are done.

require 'set'

module Que
  class Locker
    attr_reader :thread, :workers, :job_queue, :locks, :pollers, :pool

    MESSAGE_RESOLVERS = {}

    class << self
      def register_message_resolver(name, lambda)
        if MESSAGE_RESOLVERS.has_key?(name)
          raise Error, "Duplicate message resolver declaration! (#{name})"
        end

        MESSAGE_RESOLVERS[name] = lambda
      end
    end

    register_message_resolver \
      :new_job,
      -> (messages) {
        # TODO: Check for acceptance in bulk, attempt locking in bulk, push jobs
        # in bulk.
        messages.each do |message|
          if @job_queue.accept?(message) && lock_job?(message.fetch(:id))
            push_jobs([message])
          end
        end
      }

    SQL.register_sql_statement \
      :clean_lockers,
      %{
        DELETE FROM public.que_lockers
        WHERE pid = pg_backend_pid()
        OR pid NOT IN (SELECT pid FROM pg_stat_activity)
      }

    SQL.register_sql_statement \
      :register_locker,
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
        );
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

      Que.assert([TrueClass, FalseClass], listen)
      Que.assert([TrueClass, FalseClass], poll)
      Que.assert(Numeric, poll_interval)
      Que.assert(Numeric, wait_period)
      Que.assert(Integer, maximum_queue_size)
      Que.assert(Integer, minimum_queue_size)
      Que.assert(Integer, worker_count)
      Que.assert(Array, worker_priorities)
      worker_priorities.each { |p| Que.assert(Integer, p) }

      if minimum_queue_size > maximum_queue_size
        raise "minimum_queue_size (#{minimum_queue_size}) is " \
          "greater than the maximum_queue_size (#{maximum_queue_size})!"
      end

      # Local cache of which advisory locks are held by this connection.
      @locks = Set.new

      @pool =
        if connection
          # Wrap the given connection in a dummy connection pool.
          ConnectionPool.new { |&block| block.call(connection) }
        else
          Que.pool
        end

      @queue_names        = queues
      @listener           = Listener.new(pool: @pool) if listen
      @wait_period        = wait_period.to_f / 1000 # Milliseconds to seconds.
      @poll_interval      = poll_interval
      @minimum_queue_size = minimum_queue_size

      # We use a JobQueue to track sorted identifiers (priority, run_at, id) of
      # locked jobs and pass them to workers, and a ResultQueue to retrieve ids
      # of finished jobs from workers.
      @job_queue    = JobQueue.new(maximum_size: maximum_queue_size)
      @result_queue = ResultQueue.new

      if poll
        @pollers =
          queues.map do |queue|
            Poller.new(
              pool:          @pool,
              queue:         queue,
              poll_interval: poll_interval,
            )
          end
      end

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

      @thread =
        Thread.new do
          # An error causing this thread to exit is a bug in Que, which we want
          # to know about ASAP, so abort the process if it happens.
          Thread.current.abort_on_exception = true

          # Give this thread priority, so it can promptly respond to NOTIFYs.
          Thread.current.priority = 1
          work_loop
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
      checkout do |conn|
        Que.log(
          level: :debug,
          event: :locker_start,
          queues: @queue_names,
        )

        Que.internal_log :locker_start do
          {
            object_id:          object_id,
            listen:             !!@listener,
            queues:             @queue_names,
            backend_pid:        conn.backend_pid,
            wait_period:        @wait_period,
            poll_interval:      @poll_interval,
            minimum_queue_size: @minimum_queue_size,
            maximum_queue_size: @job_queue.maximum_size,
            worker_priorities:  @workers.map(&:priority),
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

          poll

          loop do
            wait
            unlock_finished_jobs

            poll
            break if @stop
          end

          Que.log(
            level: :debug,
            event: :locker_stop,
          )

          unlock_jobs(@job_queue.clear)

          @job_queue.stop
          @workers.each(&:wait_until_stopped)

          unlock_finished_jobs
        ensure
          execute :clean_lockers

          @listener.unlisten if @listener
        end
      end
    end

    extend Forwardable
    def_delegators :@pool, :execute, :checkout

    def poll
      return unless pollers
      return unless @job_queue.size < @minimum_queue_size

      space = @job_queue.space

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
      execute("SELECT pg_try_advisory_lock($1)", [id]).
        first.fetch(:pg_try_advisory_lock)
    end

    def unlock_finished_jobs
      unlock_jobs(@result_queue.clear)
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
