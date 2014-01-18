module Que
  class Worker
    attr_reader :thread

    def initialize(options)
      @job_queue    = options[:job_queue]
      @result_queue = options[:result_queue]
      @thread       = Thread.new { work_loop }
    end

    private

    def work_loop
      loop do
        begin
          job   = @job_queue.shift
          klass = Job.class_for(job[:job_class])
          klass.new(job)._run
        rescue => error
          begin
            count    = job[:error_count].to_i + 1
            interval = (klass.retry_interval if klass) || Job.retry_interval
            delay    = interval.respond_to?(:call) ? interval.call(count) : interval
            message  = "#{error.message}\n#{error.backtrace.join("\n")}"
            Que.execute :set_error, [count, delay, message] + job.values_at(:queue, :priority, :run_at, :job_id)
          rescue
            # If we can't reach the database for some reason, too bad, but
            # don't let it crash the work loop.
          end

          if Que.error_handler
            # Don't let a problem with the error handler crash the work loop.
            Que.error_handler.call(error) rescue nil
          end
        ensure
          @result_queue.push job[:job_id].to_i
        end
      end
    end
  end
end
