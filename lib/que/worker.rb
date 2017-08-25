# frozen_string_literal: true

# Workers wrap threads which continuously pull job pks from JobQueue objects,
# fetch and work those jobs, and export relevant data to ResultQueues.

module Que
  class Worker
    attr_reader :thread, :priority

    SQL[:check_job] =
      %{
        SELECT 1 AS one
        FROM public.que_jobs
        WHERE id = $1::bigint
      }

    def initialize(
      job_queue:,
      result_queue:,
      priority: nil,
      start_callback: nil
    )

      @priority     = Que.assert([NilClass, Integer], priority)
      @job_queue    = Que.assert(JobQueue, job_queue)
      @result_queue = Que.assert(ResultQueue, result_queue)

      Que.internal_log(:worker_instantiate, self) do
        {
          priority:     priority,
          job_queue:    job_queue.object_id,
          result_queue: result_queue.object_id,
        }
      end

      @thread =
        Thread.new do
          # An error causing this thread to exit is a bug in Que, which we want
          # to know about ASAP, so propagate the error if it happens.
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
      while metajob = @job_queue.shift(*priority)
        id  = metajob.id
        job = metajob.job

        Que.internal_log(:worker_received_job, self) { {id: id} }

        if Que.execute(:check_job, [id]).first
          Que.recursively_freeze(job)
          Que.internal_log(:worker_fetched_job, self) { {id: id} }

          work_job(job)
        else
          # The job was locked but doesn't exist anymore, due to a race
          # condition that exists because advisory locks don't obey MVCC. Not
          # necessarily a problem, but if it happens a lot it may be meaningful.
          Que.internal_log(:worker_job_lock_race_condition, self) { {id: id} }
        end

        Que.internal_log(:worker_pushing_finished_job, self) { {id: id} }

        @result_queue.push(
          metajob: metajob,
          message_type: :job_finished,
        )
      end
    end

    def work_job(job)
      start    = Time.now
      klass    = Que.constantize(job.fetch(:job_class))
      instance = klass.new(job)
      Que.run_middleware(instance) { instance.tap(&:_run_with_handling) }

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
    rescue => error
      Que.log(
        level: :debug,
        event: :job_errored,
        id: job.fetch(:id),
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
        job_class = (klass && klass <= Job) ? klass : Job

        delay =
          job_class.
          resolve_que_setting(
            :retry_interval,
            job.fetch(:error_count) + 1,
          )

        Que.execute :set_error, [
          delay,
          error.message.slice(0, 500),
          error.backtrace.join("\n").slice(0, 10000),
          job.fetch(:id),
        ]
      rescue
        # If we can't reach the database for some reason, too bad, but
        # don't let it crash the work loop.
      end
    end
  end
end
