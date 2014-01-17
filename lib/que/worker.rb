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
        job._run
        @result_queue.push job.attrs[:job_id]
      end
    end
  end
end
