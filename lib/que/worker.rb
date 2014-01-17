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
