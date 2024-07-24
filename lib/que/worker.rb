# frozen_string_literal: true

# Workers wrap threads which continuously pull job pks from JobBuffer objects,
# fetch and work those jobs, and export relevant data to ResultQueues.

require 'set'

module Que
  class Worker
    attr_reader :thread, :priority

    VALID_LOG_LEVELS = [:debug, :info, :warn, :error, :fatal, :unknown].to_set.freeze

    SQL[:check_job] =
      %{
        SELECT 1 AS one
        FROM public.que_jobs
        WHERE id = $1::bigint
      }

    def initialize(
      job_buffer:,
      result_queue:,
      priority: nil,
      start_callback: nil
    )

      @priority     = Que.assert([NilClass, Integer], priority)
      @job_buffer   = Que.assert(JobBuffer, job_buffer)
      @result_queue = Que.assert(ResultQueue, result_queue)

      Que.internal_log(:worker_instantiate, self) do
        {
          priority:     priority,
          job_buffer:   job_buffer.object_id,
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
      # Blocks until a job of the appropriate priority is available.
      # `fetch_next_metajob` normally returns a job to be processed.
      # If the queue is shutting down it will return false, which breaks the loop and
      # lets the thread finish.
      while (metajob = fetch_next_metajob) != false
        # If metajob is nil instead of false, we've hit a rare race condition where
        # there was a job in the buffer when the worker code checked, but the job was
        # picked up by the time we got around to shifting it off the buffer.
        # Letting this case go unhandled leads to worker threads exiting pre-maturely, so
        # we check explicitly and continue the loop.
        next if metajob.nil?
        id = metajob.id

        Que.internal_log(:worker_received_job, self) { {id: id} }

        if Que.execute(:check_job, [id]).first
          Que.recursively_freeze(metajob.job)
          Que.internal_log(:worker_fetched_job, self) { {id: id} }

          work_job(metajob)
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

    def fetch_next_metajob
      @job_buffer.shift(*priority)
    end

    def work_job(metajob)
      job      = metajob.job
      start    = Time.now
      klass    = Que.constantize(job.fetch(:job_class))
      instance = klass.new(job)

      Que.run_job_middleware(instance) { instance.tap(&:_run) }

      elapsed = Time.now - start

      log_level =
        if instance.que_error
          :error
        else
          instance.log_level(elapsed)
        end

      if VALID_LOG_LEVELS.include?(log_level)
        log_message = {
          level: log_level,
          job: metajob.job,
          elapsed: elapsed,
        }

        if error = instance.que_error
          log_message[:event] = :job_errored
          log_message[:error] = "#{error.class}: #{error.message}".slice(0, 500)
        else
          log_message[:event] = :job_worked
        end

        Que.log(**log_message)
      end

      instance
    rescue => error
      Que.log(
        level: :debug,
        event: :job_errored,
        job: metajob.job,
        error: {
          class:   error.class.to_s,
          message: error.message,
          backtrace: (error.backtrace || []).join("\n").slice(0, 10000),
        },
      )

      Que.notify_error(error)

      begin
        # If the Job class couldn't be resolved, use the default retry
        # backoff logic in Que::Job.
        job_class = (klass && klass <= Job) ? klass : Job

        error_count = job.fetch(:error_count) + 1

        max_retry_count = job_class.resolve_que_setting(:maximum_retry_count)

        if max_retry_count && error_count > max_retry_count
          Que.execute :expire_job, [job.fetch(:id)]
        else
          delay =
            job_class.
            resolve_que_setting(
              :retry_interval,
              error_count,
            )

          Que.execute :set_error, [
            delay,
            "#{error.class}: #{error.message}".slice(0, 500),
            (error.backtrace || []).join("\n").slice(0, 10000),
            job.fetch(:id),
          ]
        end
      rescue
        # If we can't reach the database for some reason, too bad, but
        # don't let it crash the work loop.
      end

      error
    end
  end
end
