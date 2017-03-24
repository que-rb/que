# frozen_string_literal: true

# The Locker class encapsulates a thread that is listening/polling for new
# jobs in the DB, locking them, passing their primary keys to workers, then
# cleaning up by unlocking them once the workers are done.

require 'forwardable'
require 'set'

module Que
  class Locker
    attr_reader :thread, :workers, :job_queue, :backend_pid, :locks

    DEFAULT_POLL_INTERVAL      = 1.0
    DEFAULT_WAIT_PERIOD        = 0.01
    DEFAULT_MINIMUM_QUEUE_SIZE = 2
    DEFAULT_MAXIMUM_QUEUE_SIZE = 8
    DEFAULT_WORKER_COUNT       = 6
    DEFAULT_WORKER_PRIORITIES  = [10, 30, 50].freeze

    def initialize(
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

      @locks = Set.new

      # Wrap the given connection in a dummy connection pool.
      if connection
        @pool = ConnectionPool.new { |&block| block.call(connection) }
      end

      @listen             = listen
      @wait_period        = wait_period
      @poll_interval      = poll_interval
      @minimum_queue_size = minimum_queue_size

      # We use one JobQueue to send primary keys of reserved jobs to workers,
      # and another to retrieve primary keys of finished jobs from workers.
      @job_queue    = JobQueue.new maximum_size: maximum_queue_size
      @result_queue = ResultQueue.new

      @workers = worker_count.times.zip(worker_priorities).map do |_, priority|
        Worker.new priority:       priority,
                   job_queue:      @job_queue,
                   result_queue:   @result_queue,
                   start_callback: on_worker_start
      end

      @thread = Thread.new { work_loop }
      @thread.priority = 1
    end

    def stop!
      stop
      wait_for_stop
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
        @backend_pid =
          execute("SELECT pg_backend_pid()").first[:pg_backend_pid]

        Que.log \
          level:              :debug,
          event:              :locker_start,
          listen:             @listen,
          backend_pid:        @backend_pid,
          wait_period:        @wait_period,
          poll_interval:      @poll_interval,
          minimum_queue_size: @minimum_queue_size,
          maximum_queue_size: @job_queue.maximum_size,
          worker_priorities:  @workers.map(&:priority)

        begin
          if @listen
            execute "LISTEN que_locker_#{@backend_pid}"
          end

          # A previous locker that didn't exit cleanly may have left behind
          # a bad locker record, so clean up before registering.
          execute :clean_lockers
          execute :register_locker, [
            @workers.count,
            Process.pid,
            CURRENT_HOSTNAME, 
            @listen.to_s
          ]

          poll

          loop do
            wait
            unlock_finished_jobs

            poll if queue_refill_needed? || poll_interval_elapsed?
            break if @stop
          end

          Que.log \
            level: :debug,
            event: :locker_stop

          unlock_jobs(@job_queue.clear)

          @job_queue.stop
          @workers.each(&:wait_until_stopped)

          unlock_finished_jobs
        ensure
          execute "DELETE FROM public.que_lockers WHERE pid = $1", [@backend_pid]

          if @listen
            # Unlisten and drain notifications before releasing connection back
            # to the pool.
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
      jobs  = execute :poll_jobs, ["{#{@locks.to_a.join(',')}}", space]

      @locks.merge jobs.map { |job| job[:id] }
      push_jobs(jobs)

      @last_polled_at      = Time.now
      @last_poll_satisfied = space == jobs.count

      Que.log \
        level: :debug,
        event: :locker_polled,
        limit: space,
        locked: jobs.count
    end

    def wait
      if @listen
        # TODO: In case we received notifications for many jobs at once, check
        # and lock and push them all in bulk.
        if identifiers = wait_for_job(@wait_period)
          if @job_queue.accept?(identifiers) && lock_job?(identifiers[:id])
            push_jobs([identifiers])
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

      @locks.add(id)
      true
    end

    def lock_job(id)
      execute("SELECT pg_try_advisory_lock($1)", [id]).
        first[:pg_try_advisory_lock]
    end

    def unlock_finished_jobs
      unlock_jobs(@result_queue.clear)
    end

    def push_jobs(identifiers)
      # Unlock any low-importance jobs the new ones may displace.
      if ids = @job_queue.push(*identifiers)
        unlock_jobs(ids)
      end
    end

    def unlock_jobs(ids)
      # TODO: This could be made more efficient.
      ids.each do |id|
        execute "SELECT pg_advisory_unlock($1)", [id]
        @locks.delete(id)
      end
    end

    def wait_for_job(timeout = nil)
      checkout do |conn|
        conn.wait_for_notify(timeout) do |_, _, payload|
          job_json =
            JSON.parse(payload, symbolize_names: true)

          Que.log \
            level: :debug,
            event: :job_notified,
            job: job_json

          job_json[:run_at] = Time.parse(job_json[:run_at])

          return job_json
        end
      end
    end
  end
end
