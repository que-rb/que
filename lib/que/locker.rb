# frozen_string_literal: true

# The Locker class encapsulates a thread that is listening/polling for new
# jobs in the DB, locking them, passing their primary keys to workers, then
# cleaning up by unlocking them once the workers are done.

require 'forwardable'
require 'set'

module Que
  class Locker
    attr_reader :thread, :workers, :job_queue, :locks, :pollers

    DEFAULT_POLL_INTERVAL      = 1.0
    DEFAULT_WAIT_PERIOD        = 0.01
    DEFAULT_MINIMUM_QUEUE_SIZE = 2
    DEFAULT_MAXIMUM_QUEUE_SIZE = 8
    DEFAULT_WORKER_COUNT       = 6
    DEFAULT_WORKER_PRIORITIES  = [10, 30, 50].freeze

    def initialize(
      queues:             [Que.default_queue],
      connection:         nil,
      listen:             true,
      poll_interval:      DEFAULT_POLL_INTERVAL,
      wait_period:        DEFAULT_WAIT_PERIOD,
      minimum_queue_size: DEFAULT_MINIMUM_QUEUE_SIZE,
      maximum_queue_size: DEFAULT_MAXIMUM_QUEUE_SIZE,
      worker_count:       DEFAULT_WORKER_COUNT,
      worker_priorities:  DEFAULT_WORKER_PRIORITIES,
      on_worker_start:    nil
    )

      # Local cache of which advisory locks are held by this connection.
      @locks = Set.new

      # Wrap the given connection in a dummy connection pool.
      if connection
        @pool = ConnectionPool.new { |&block| block.call(connection) }
      end

      @queue_names        = queues
      @listen             = listen
      @wait_period        = wait_period
      @poll_interval      = poll_interval
      @minimum_queue_size = minimum_queue_size

      # We use a JobQueue to track sorted identifiers (priority, run_at, id) of
      # locked jobs and pass them to workers, and a ResultQueue to retrieve ids
      # of finished jobs from workers.
      @job_queue    = JobQueue.new maximum_size: maximum_queue_size
      @result_queue = ResultQueue.new

      # If the worker_count exceeds the array of priorities it'll result in
      # extra workers that will work jobs of any priority. For example, the
      # default worker_count of 6 and the default worker priorities of [10, 30,
      # 50] will result in three workers that only work jobs that meet those
      # priorities, and three workers that will work any job.
      @workers = worker_count.times.zip(worker_priorities).map do |_, priority|
        Worker.new(
          priority:       priority,
          job_queue:      @job_queue,
          result_queue:   @result_queue,
          start_callback: on_worker_start,
        )
      end

      @thread = Thread.new { work_loop }

      # Give the locker thread priority, so it can promptly respond to NOTIFYs.
      @thread.priority = 1
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
          level:              :debug,
          event:              :locker_start,
          listen:             @listen,
          queues:             @queue_names,
          backend_pid:        conn.backend_pid,
          wait_period:        @wait_period,
          poll_interval:      @poll_interval,
          minimum_queue_size: @minimum_queue_size,
          maximum_queue_size: @job_queue.maximum_size,
          worker_priorities:  @workers.map(&:priority),
        )

        begin
          execute "LISTEN que_locker_#{conn.backend_pid}" if @listen

          # A previous locker that didn't exit cleanly may have left behind
          # a bad locker record, so clean up before registering.
          execute :clean_lockers
          execute :register_locker, [
            @workers.count,
            Process.pid,
            CURRENT_HOSTNAME, 
            @listen,
            "{\"#{@queue_names.join('","')}\"}",
          ]

          poll

          loop do
            wait
            unlock_finished_jobs

            poll if queue_refill_needed? || poll_interval_elapsed?
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

          if @listen
            # Unlisten and drain notifications before releasing the connection.
            execute "UNLISTEN *"
            {} while conn.notifies
          end
        end
      end
    end

    private

    extend Forwardable
    def_delegators :pool, :execute, :checkout

    def pool
      @pool || Que.pool
    end

    def poll
      space = @job_queue.space

      sort_keys =
        execute(
          :poll_jobs,
          [
            @queue_names.first,
            "{#{@locks.to_a.join(',')}}",
            space
          ]
        )

      sort_keys.each do |sort_key|
        mark_id_as_locked(sort_key.fetch(:id))
      end

      push_jobs(sort_keys)

      @last_polled_at      = Time.now
      @last_poll_satisfied = space == sort_keys.count

      Que.log(
        level: :debug,
        event: :locker_polled,
        limit: space,
        locked: sort_keys.count,
      )
    end

    def wait
      if @listen
        # TODO: In case we receive notifications for many jobs at once, check
        # and lock and push them all in bulk.
        if sort_key = wait_for_job(@wait_period)
          if @job_queue.accept?(sort_key) && lock_job?(sort_key.fetch(:id))
            push_jobs([sort_key])
          end
        end
      else
        sleep(@wait_period)
      end
    end

    def queue_refill_needed?
      @last_poll_satisfied && @job_queue.size <= @minimum_queue_size
    end

    def poll_interval_elapsed?
      @poll_interval && (Time.now - @last_polled_at) > @poll_interval
    end

    def lock_job?(id)
      return false if @locks.include?(id)
      return false unless lock_job(id)

      mark_id_as_locked(id)
      true
    end

    def lock_job(id)
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

      # TODO: Assert that these always return true.
      execute "SELECT pg_advisory_unlock(v.i) FROM (VALUES (#{values})) v (i)"

      ids.each { |id| @locks.delete(id) }
    end

    def mark_id_as_locked(id)
      Que.assert(@locks.add?(id)) do
        "Job erroneously locked a second time: #{id}"
      end
    end

    def wait_for_job(timeout = nil)
      checkout do |conn|
        conn.wait_for_notify(timeout) do |_, _, payload|
          sort_key =
            JSON.parse(payload, symbolize_names: true)

          Que.log(
            level: :debug,
            event: :job_notified,
            job:   sort_key,
          )

          sort_key[:run_at] = Time.parse(sort_key.fetch(:run_at))

          return sort_key
        end
      end
    end
  end
end
