module Que
  class Listener
    attr_reader :thread

    def initialize(options = {})
      @queue_name   = options[:queue] || ''
      @job_queue    = JobQueue.new
      @result_queue = ResultQueue.new

      @workers = (options[:worker_count] || 4).times.map do
        Worker.new :job_queue    => @job_queue,
                   :result_queue => @result_queue
      end

      @thread = Thread.new { work_loop }
    end

    def stop
      @stop = true
    end

    def wait_until_stopped
      sleep 0.0001 while @thread.status
    end

    private

    def work_loop
      Que.adapter.checkout do
        begin
          # A previous listener that didn't exit cleanly may have left behind
          # a bad listener record, so clean up before doing anything.
          Que.execute :clean_listeners
          Que.execute :register_listener, [@queue_name, @workers.count, Process.pid, Socket.gethostname]

          loop do
            sleep 0.0001
            break if @stop
          end
        ensure
          Que.execute "DELETE FROM que_listeners WHERE pid = pg_backend_pid()"
        end
      end
    end
  end
end
