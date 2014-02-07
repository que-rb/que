require 'set'
require 'socket'

module Que
  class Locker
    attr_reader :thread, :workers, :job_queue

    # When in the wait loop, wake up at least every 10 ms to check what's going on.
    WAIT_PERIOD = 0.01

    def initialize(options = {})
      @listening          = !!options[:listening]
      @queue_name         = options[:queue]              || ''
      @poll_interval      = options[:poll_interval]      || 5
      @minimum_queue_size = options[:minimum_queue_size] || 2

      @locks        = Set.new
      @job_queue    = JobQueue.new :maximum_size => options[:maximum_queue_size] || 8
      @result_queue = ResultQueue.new

      worker_count      = options[:worker_count]      || 6
      worker_priorities = options[:worker_priorities] || [10, 30, 50]

      @workers = worker_count.times.zip(worker_priorities).map do |_, priority|
        Worker.new :priority     => priority,
                   :job_queue    => @job_queue,
                   :result_queue => @result_queue
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
      Que.adapter.checkout do
        backend_pid = Que.execute("SELECT pg_backend_pid()").first[:pg_backend_pid]

        begin
          Que.execute "LISTEN que_locker_#{backend_pid}" if @listening

          # A previous locker that didn't exit cleanly may have left behind
          # a bad locker record, so clean up before registering.
          Que.execute :clean_lockers
          Que.execute :register_locker, [@queue_name, @workers.count, Process.pid, Socket.gethostname, @listening]

          poll

          loop do
            wait
            unlock_finished_jobs

            poll if queue_refill_needed? || poll_interval_elapsed?
            break if @stop
          end

          unlock_jobs(@job_queue.clear)

          @job_queue.stop
          @workers.each(&:wait_until_stopped)

          unlock_finished_jobs
        ensure
          Que.execute "DELETE FROM que_lockers WHERE pid = $1", [backend_pid]

          if @listening
            Que.execute "UNLISTEN *"
            Que.adapter.drain_notifications
          end
        end
      end
    end

    private

    def poll
      count = @job_queue.space
      jobs  = Que.execute :poll_jobs, [@queue_name, "{#{@locks.to_a.join(',')}}", count]

      @locks.merge jobs.map { |pk| pk[:job_id] }
      push_jobs *jobs

      @last_polled_at      = Time.now
      @last_poll_satisfied = count == jobs.count
    end

    def wait
      if @listening
        if pk = Que.adapter.wait_for_json(WAIT_PERIOD)
          pk['run_at'] = Time.parse(pk['run_at'])

          push_jobs(pk) if @job_queue.accept?(pk) && lock_job?(pk[:job_id])
        end
      else
        sleep WAIT_PERIOD
      end
    end

    def queue_refill_needed?
      @last_poll_satisfied && @job_queue.size <= @minimum_queue_size
    end

    def poll_interval_elapsed?
      (Time.now - @last_polled_at) > @poll_interval
    end

    def lock_job?(id)
      if !@locks.include?(id) && Que.execute("SELECT pg_try_advisory_lock($1)", [id]).first[:pg_try_advisory_lock]
        @locks.add(id)
        true
      end
    end

    def unlock_finished_jobs
      unlock_jobs @result_queue.clear
    end

    def push_jobs(*pks)
      # Unlock any low-importance jobs the new ones may displace.
      if ids = @job_queue.push(pks)
        unlock_jobs(ids)
      end
    end

    def unlock_jobs(ids)
      ids.each do |id|
        Que.execute "SELECT pg_advisory_unlock($1)", [id]
        @locks.delete(id)
      end
    end
  end
end
