module Que
  class Worker
    attr_reader :thread
    attr_accessor :priority

    def initialize(options)
      @priority     = options[:priority]
      @job_queue    = options[:job_queue]
      @result_queue = options[:result_queue]

      @thread = Thread.new { work_loop }
      @thread.abort_on_exception = true
    end

    def wait_until_stopped
      @thread.join
    end

    private

    def work_loop
      loop do
        break unless pk = @job_queue.shift(*priority)

        begin
          if job = Que.execute(:get_job, pk).first
            klass = Job.class_for(job[:job_class])
            instance = klass.new(job)

            start = Time.now
            instance._run
            Que.log :event => :job_worked, :job => job, :elapsed => (Time.now - start)
          else
            Que.log :event => :job_race_condition, :pk => pk
          end
        rescue => error
          Que.log :event => :job_errored, :pk => pk, :job => job, :error => {:class => error.class.to_s, :message => error.message}

          begin
            count    = job[:error_count] + 1
            interval = (klass.retry_interval if klass && klass.respond_to?(:retry_interval)) || Job.retry_interval
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
          @result_queue.push(pk)
        end
      end
    end
  end
end
