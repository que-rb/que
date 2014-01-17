module Que
  class Worker
    def initialize(options)
      @job_queue    = options[:job_queue]
      @result_queue = options[:result_queue]
      @thread       = Thread.new { work_loop }
    end

    private

    def work_loop
      loop do
        job = @job_queue.shift

        begin
          job._run
        rescue => error
          begin
            attrs    = job.attrs
            count    = attrs[:error_count].to_i + 1
            interval = job.class.retry_interval || Job.retry_interval
            delay    = interval.respond_to?(:call) ? interval.call(count) : interval
            message  = "#{error.message}\n#{error.backtrace.join("\n")}"
            Que.execute :set_error, [count, delay, message] + attrs.values_at(:queue, :priority, :run_at, :job_id)
          rescue
            # If we can't reach the database for some reason, too bad, but
            # don't let it crash the work loop.
          end

          if Que.error_handler
            # Don't let a problem with the error handler crash the work loop.
            Que.error_handler.call(error) rescue nil
          end
        ensure
          @result_queue.push job.attrs[:job_id]
        end
      end
    end
  end
end
