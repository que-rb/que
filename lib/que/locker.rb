require 'set'
require 'socket'

module Que
  class Locker
    attr_reader :thread, :workers, :job_queue

    def initialize(options = {})
      @queue_name    = options[:queue] || ''
      @listening     = !!options[:listening]
      @poll_interval = options[:poll_interval] || 5

      @locks        = Set.new
      @job_queue    = JobQueue.new :maximum_size => options[:maximum_queue_size]
      @result_queue = ResultQueue.new

      @workers = (options[:worker_count] || 4).times.zip(options[:worker_priorities] || []).map do |_, priority|
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

          poll 10

          loop do
            wait
            break if @stop

            poll 5
            break if @stop
          end

          @job_queue.clear.each { |id| unlock_job(id) }
          @job_queue.stop
          @workers.each(&:wait_until_stopped)

          unlock_finished_jobs
        ensure
          Que.execute "UNLISTEN *"
          Que.execute "DELETE FROM que_lockers WHERE pid = $1", [backend_pid]
          Que.adapter.drain_notifications
        end
      end
    end

    private

    # When waiting, wake up every 10 ms to check what's going on.
    SLEEP_PERIOD = 0.01

    def wait
      loop do
        if @listening
          if pk = Que.adapter.wait_for_job(SLEEP_PERIOD)
            pk['run_at'] = Time.parse(pk['run_at'])
            if lock_job?(pk[:job_id])
              if ids = @job_queue.push(pk)
                ids.each { |id| unlock_job(id) }
              end
            end
          end
        else
          sleep SLEEP_PERIOD
        end

        unlock_finished_jobs
        break if stop_waiting?
      end
    end

    def stop_waiting?
      if @stop
        # Bail if the locker should be stopping.
        true
      elsif @last_poll_satisfied
        # If the last poll returned all the jobs we asked it to, assume
        # there's a backlog and go back for more when the queue runs low.
        @job_queue.size <= 5
      else
        # There's no backlog, so we wait until the poll_interval has elapsed.
        time_until_next_poll.zero?
      end
    end

    def lock_job?(id)
      id = id.to_i
      if !@locks.include?(id) && Que.execute("SELECT pg_try_advisory_lock($1)", [id]).first[:pg_try_advisory_lock]
        @locks.add(id)
        true
      end
    end

    def unlock_job(id)
      id = id.to_i
      Que.execute "SELECT pg_advisory_unlock($1)", [id]
      @locks.delete(id)
    end

    def unlock_finished_jobs
      while id = @result_queue.shift
        unlock_job(id)
      end
    end

    def poll(count)
      jobs = Que.execute(:poll_jobs, [@queue_name, "{#{@locks.to_a.join(',')}}", count])

      jobs.each do |pk|
        @locks.add(pk[:job_id])
        if ids = @job_queue.push(pk)
          ids.each { |id| unlock_job(id) }
        end
      end

      @last_polled_at      = Time.now
      @last_poll_satisfied = count == jobs.count
    end

    def time_until_next_poll
      wait = @poll_interval - (Time.now - @last_polled_at)
      wait > 0 ? wait : 0
    end
  end
end
