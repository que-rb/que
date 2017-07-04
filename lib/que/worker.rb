# frozen_string_literal: true

# Workers basically wrap threads which continuously pull job ids from JobQueue
# objects, fetch and work those jobs, then pass their ids to ResultQueues to be
# unlocked.

module Que
  class Worker
    attr_reader :thread, :priority

    def initialize(
      job_queue:,
      result_queue:,
      priority: nil,
      start_callback: nil
    )

      @priority     = Que.assert([NilClass, Integer], priority)
      @job_queue    = Que.assert(JobQueue, job_queue)
      @result_queue = Que.assert(ResultQueue, result_queue)

      @thread =
        Thread.new do
          # An error causing this thread to exit is a bug in Que, which we want
          # to know about ASAP, so abort the process if it happens.
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
      # Blocks until a job of the appropriate priority is available. If the
      # queue is shutting down this will return nil, which breaks the loop and
      # lets the thread finish.
      while id = @job_queue.shift(*priority)
        begin
          if job = Que.execute(:get_job, [id]).first
            start    = Time.now
            klass    = Que.constantize(job.fetch(:job_class))
            instance = klass.new(job)
            instance._run

            log_message = {
              level: :debug,
              job: job,
              elapsed: (Time.now - start),
            }

            if e = instance.que_error
              log_message[:event] = :job_errored
              # TODO: Convert this to a string manually?
              log_message[:error] = e
            else
              log_message[:event] = :job_worked
            end

            Que.log(log_message)
          else
            # The job was locked but doesn't exist anymore, due to a race
            # condition that exists because advisory locks don't obey MVCC. Not
            # necessarily a problem, but if it happens a lot it may be
            # meaningful somehow, so log it.
            Que.log(
              level: :debug,
              event: :job_race_condition,
              id:    id,
            )
          end
        rescue => error
          Que.log(
            level: :debug,
            event: :job_errored,
            id: id,
            job: job,
            error: {
              class:   error.class.to_s,
              message: error.message,
            },
          )

          Que.notify_error(error)

          begin
            # If the Job class couldn't be resolved, use the default retry
            # backoff logic in Que::Job.
            job_class =
              if klass && klass <= Job
                klass
              else
                Job
              end

            delay =
              job_class.
              resolve_setting(
                :retry_interval,
                job.fetch(:error_count) + 1,
              )

            Que.execute :set_error, [
              delay,
              error.message,
              error.backtrace.join("\n"),
              id,
            ]
          rescue
            # If we can't reach the database for some reason, too bad, but
            # don't let it crash the work loop.
          end
        ensure
          @result_queue.push(id)
        end
      end
    end
  end
end
