# frozen_string_literal: true

# Workers basically wrap threads, which continually pull primary keys of jobs
# from internal JobQueue objects, fetch and work those jobs, then pass their
# ids to ResultQueues to be unlocked.

module Que
  class Worker
    attr_reader :thread
    attr_accessor :priority

    def initialize(job_queue:, result_queue:, priority: nil, start_callback: nil)
      @priority     = priority
      @job_queue    = job_queue
      @result_queue = result_queue

      @thread = Thread.new do
        Thread.current.abort_on_exception = true
        start_callback.call(self) if start_callback.respond_to?(:call)
        work_loop
      end
    end

    def wait_until_stopped
      @thread.join
    end

    private

    def work_loop
      loop do
        # Blocks until a job of the appropriate priority is available. If the
        # queue is shutting down this returns nil, which breaks the loop and
        # ends the thread.
        break unless pk = @job_queue.shift(*priority)

        begin
          if job = Que.execute(:get_job, pk).first
            start = Time.now
            klass = Que.constantizer.call(job[:job_class])
            instance = klass.new(job)
            instance._run
            Que.log level: :debug, event: :job_worked, job: job, elapsed: (Time.now - start)
          else
            # The job was locked but doesn't exist anymore, due to the race
            # condition that exists because advisory locks don't obey MVCC.
            # Not necessarily a problem, but if it happens a lot it may be
            # meaningful somehow, so log it.
            Que.log level: :debug, event: :job_race_condition, pk: pk
          end
        rescue => error
          Que.log level: :debug,
                  event: :job_errored,
                  pk: pk,
                  job: job,
                  error: {
                    class: error.class.to_s,
                    message: error.message
                  }

          begin
            count    = job[:error_count] + 1
            interval = (klass.retry_interval if klass && klass.respond_to?(:retry_interval)) || Job.retry_interval
            delay    = interval.respond_to?(:call) ? interval.call(count) : interval
            message  = "#{error.message}\n#{error.backtrace.join("\n")}"
            Que.execute :set_error, [count, delay, message] + job.values_at(:priority, :run_at, :job_id)
          rescue
            # If we can't reach the database for some reason, too bad, but
            # don't let it crash the work loop.
          end

          if Que.error_handler
            begin
              # Don't let a problem with the error handler crash the work loop.
              Que.error_handler.call(error, job)
            rescue => error_handler_error
              # What handles errors from the error handler? Nothing, so just log loudly.
              Que.log level: :error,
                      event: :error_handler_errored,
                      job: job,
                      original_error: {
                        class: error.class.to_s,
                        message: error.message
                      },
                      error_handler_error: {
                        class: error_handler_error.class.to_s,
                        message: error_handler_error.message,
                        backtrace: error_handler_error.backtrace
                      }
            end
          end
        ensure
          @result_queue.push(pk)
        end
      end
    end
  end
end
