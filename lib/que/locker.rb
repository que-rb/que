# frozen_string_literal: true

# The Locker class encapsulates a thread that is listening/polling for new
# jobs in the DB, locking them, passing their primary keys to workers, then
# cleaning up by unlocking them once the workers are done.

require 'forwardable'
require 'set'

module Que
  class Locker
    attr_reader :thread, :workers, :job_queue

    def initialize(connection: nil, listen: true, wait_period: 0.01, poll_interval: nil, minimum_queue_size: 2, maximum_queue_size: 8, worker_count: 6, worker_priorities: [10, 30, 50])
      @locks = Set.new

      # Wrap the given connection in a dummy connection pool.
      @pool = ConnectionPool.new { |&block| block.call(connection) } if connection

      @listen             = listen
      @wait_period        = wait_period
      @poll_interval      = poll_interval
      @minimum_queue_size = minimum_queue_size

      # We use one JobQueue to send primary keys of reserved jobs to workers,
      # and another to retrieve primary keys of finished jobs from workers.
      @job_queue    = JobQueue.new maximum_size: maximum_queue_size
      @result_queue = ResultQueue.new

      @workers = worker_count.times.zip(worker_priorities).map do |_, priority|
        Worker.new priority:     priority,
                   job_queue:    @job_queue,
                   result_queue: @result_queue
      end

      @thread = Thread.new { work_loop }
      @thread.priority = 1
    end

    def stop
      @stop = true
      @thread.join
    end

    private

    def work_loop
      checkout do |conn|
        backend_pid = execute("SELECT pg_backend_pid()").first[:pg_backend_pid]

        Que.log level:              :debug,
                event:              :locker_start,
                listen:             @listen,
                backend_pid:        backend_pid,
                wait_period:        @wait_period,
                poll_interval:      @poll_interval,
                minimum_queue_size: @minimum_queue_size,
                maximum_queue_size: @job_queue.maximum_size,
                worker_priorities:  @workers.map(&:priority)

        begin
          execute "LISTEN que_locker_#{backend_pid}" if @listen

          # A previous locker that didn't exit cleanly may have left behind
          # a bad locker record, so clean up before registering.
          execute :clean_lockers
          execute :register_locker, [@workers.count, Process.pid, Socket.gethostname, @listen.to_s]

          poll

          loop do
            wait
            unlock_finished_jobs

            poll if queue_refill_needed? || poll_interval_elapsed?
            break if @stop
          end

          Que.log level: :debug, event: :locker_stop

          unlock_jobs(@job_queue.clear)

          @job_queue.stop
          @workers.each(&:wait_until_stopped)

          unlock_finished_jobs
        ensure
          execute "DELETE FROM que_lockers WHERE pid = $1", [backend_pid]

          if @listen
            # Unlisten and drain notifications before returning connection to pool.
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
      count = @job_queue.space
      jobs  = execute :poll_jobs, ["{#{@locks.to_a.join(',')}}", count]

      @locks.merge jobs.map { |job| job[:job_id] }
      push_jobs jobs.map { |job| job.values_at(:priority, :run_at, :job_id) }

      @last_polled_at      = Time.now
      @last_poll_satisfied = count == jobs.count

      Que.log level: :debug, event: :locker_polled, limit: count, locked: jobs.count
    end

    def wait
      if @listen
        if pk = wait_for_job(@wait_period)
          push_jobs([pk]) if @job_queue.accept?(pk) && lock_job?(pk[-1])
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
      if !@locks.include?(id) && execute("SELECT pg_try_advisory_lock($1)", [id]).first[:pg_try_advisory_lock]
        @locks.add(id)
        true
      end
    end

    def unlock_finished_jobs
      unlock_jobs(@result_queue.clear)
    end

    def push_jobs(pks)
      # Unlock any low-importance jobs the new ones may displace.
      if pks = @job_queue.push(*pks)
        unlock_jobs(pks)
      end
    end

    def unlock_jobs(pks)
      pks.each do |pk|
        id = pk[-1]
        execute "SELECT pg_advisory_unlock($1)", [id]
        @locks.delete(id)
      end
    end

    def wait_for_job(timeout = nil)
      checkout do |conn|
        conn.wait_for_notify(timeout) do |_, _, payload|
          Que.log level: :debug, event: :job_notified, job: (json = Que.json_module.load(payload))
          return [json['priority'], Time.parse(json['run_at']), json['job_id']]
        end
      end
    end
  end
end
