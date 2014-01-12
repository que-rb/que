module Que
  class Job
    attr_reader :attrs

    def initialize(attrs)
      @attrs        = attrs
      @attrs[:args] = Que.indifferentiate JSON_MODULE.load(@attrs[:args])
    end

    # Subclasses should define their own run methods, but keep an empty one
    # here so that Que::Job.queue can queue an empty job in testing.
    def run(*args)
    end

    def _run
      run *attrs[:args]
      destroy unless @destroyed
    end

    private

    def destroy
      Que.execute :destroy_job, attrs.values_at(:priority, :run_at, :job_id)
      @destroyed = true
    end

    class << self
      def queue(*args)
        if args.last.is_a?(Hash)
          options  = args.pop
          run_at   = options.delete(:run_at)
          priority = options.delete(:priority)
          args << options if options.any?
        end

        attrs = {:job_class => to_s, :args => JSON_MODULE.dump(args)}

        if time = run_at || @default_run_at && @default_run_at.call
          attrs[:run_at] = time
        end

        if pty = priority || @default_priority
          attrs[:priority] = pty
        end

        if Que.mode == :sync && !time
          run_job(attrs)
        else
          values = Que.execute(:insert_job, attrs.values_at(:priority, :run_at, :job_class, :args)).first
          Que.adapter.wake_worker_after_commit unless time
          new(values)
        end
      end

      def work
        # Since we're taking session-level advisory locks, we have to hold the
        # same connection throughout the process of getting a job, working it,
        # deleting it, and removing the lock.
        Que.adapter.checkout do
          begin
            if job = Que.execute(:lock_job).first
              # Edge case: It's possible for the lock_job query to have
              # grabbed a job that's already been worked, if it took its MVCC
              # snapshot while the job was processing, but didn't attempt the
              # advisory lock until it was finished. Since we have the lock, a
              # previous worker would have deleted it by now, so we just
              # double check that it still exists before working it.

              # Note that there is currently no spec for this behavior, since
              # I'm not sure how to reliably commit a transaction that deletes
              # the job in a separate thread between lock_job and check_job.
              if Que.execute(:check_job, job.values_at(:priority, :run_at, :job_id)).none?
                :job_race_condition
              else
                [:job_worked, run_job(job)]
              end
            else
              :job_unavailable
            end
          rescue => error
            begin
              if job
                # Borrowed the backoff formula and error data format from delayed_job.
                count   = job[:error_count].to_i + 1
                delay   = count ** 4 + 3
                message = "#{error.message}\n#{error.backtrace.join("\n")}"
                Que.execute :set_error, [count, delay, message] + job.values_at(:priority, :run_at, :job_id)
              end
            rescue
              # If we can't reach the database for some reason, too bad, but
              # don't let it crash the work loop.
            end

            if Que.error_handler
              # Similarly, protect the work loop from a failure of the error handler.
              Que.error_handler.call(error) rescue nil
            end

            return [:job_errored, error]
          ensure
            # Clear the advisory lock we took when locking the job. Important
            # to do this so that they don't pile up in the database. Again, if
            # we can't reach the database, don't crash the work loop.
            begin
              Que.execute "SELECT pg_advisory_unlock($1)", [job[:job_id]] if job
            rescue
            end
          end
        end
      end

      private

      def run_job(attrs)
        attrs[:job_class].split('::').inject(Object, &:const_get).new(attrs).tap(&:_run)
      end
    end
  end
end
