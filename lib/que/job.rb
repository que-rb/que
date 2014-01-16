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

    # Sort jobs by their priority, run_at time, and job_id in that order.
    def <=>(other)
      attrs.values_at(:priority, :run_at, :job_id) <=> other.attrs.values_at(:priority, :run_at, :job_id)
    end

    private

    def destroy
      Que.execute :destroy_job, attrs.values_at(:queue, :priority, :run_at, :job_id)
      @destroyed = true
    end

    @retry_interval = proc { |count| count ** 4 + 3 }

    class << self
      attr_reader :retry_interval

      def queue(*args)
        if args.last.is_a?(Hash)
          options  = args.pop
          queue    = options.delete(:queue) || '' if options.key?(:queue)
          run_at   = options.delete(:run_at)
          priority = options.delete(:priority)
          args << options if options.any?
        end

        attrs = {:job_class => to_s, :args => JSON_MODULE.dump(args)}

        if t = run_at || @default_run_at && @default_run_at.call
          attrs[:run_at] = t
        end

        if p = priority || @default_priority
          attrs[:priority] = p
        end

        if q = queue || @queue
          attrs[:queue] = q
        end

        if Que.mode == :sync && !t
          class_for(attrs[:job_class]).new(attrs).tap(&:_run)
        else
          values = Que.execute(:insert_job, attrs.values_at(:queue, :priority, :run_at, :job_class, :args)).first
          new(values)
        end
      end

      def work(queue = '')
        # Since we're taking session-level advisory locks, we have to hold the
        # same connection throughout the process of getting a job, working it,
        # deleting it, and removing the lock.
        Que.adapter.checkout do
          begin
            if job = Que.execute(:lock_job, [queue]).first
              # Edge case: It's possible for the lock_job query to have
              # grabbed a job that's already been worked, if it took its MVCC
              # snapshot while the job was processing, but didn't attempt the
              # advisory lock until it was finished. Since we have the lock, a
              # previous worker would have deleted it by now, so we just
              # double check that it still exists before working it.

              # Note that there is currently no spec for this behavior, since
              # I'm not sure how to reliably commit a transaction that deletes
              # the job in a separate thread between lock_job and check_job.
              if Que.execute(:check_job, job.values_at(:queue, :priority, :run_at, :job_id)).none?
                {:event => :job_race_condition}
              else
                klass = class_for(job[:job_class])
                klass.new(job)._run
                {:event => :job_worked, :job => job}
              end
            else
              {:event => :job_unavailable}
            end
          rescue => error
            begin
              if job
                count    = job[:error_count].to_i + 1
                interval = klass && klass.retry_interval || retry_interval
                delay    = interval.respond_to?(:call) ? interval.call(count) : interval
                message  = "#{error.message}\n#{error.backtrace.join("\n")}"
                Que.execute :set_error, [count, delay, message] + job.values_at(:queue, :priority, :run_at, :job_id)
              end
            rescue
              # If we can't reach the database for some reason, too bad, but
              # don't let it crash the work loop.
            end

            if Que.error_handler
              # Similarly, protect the work loop from a failure of the error handler.
              Que.error_handler.call(error) rescue nil
            end

            return {:event => :job_errored, :error => error, :job => job}
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

      def class_for(string)
        string.split('::').inject(Object, &:const_get)
      end
    end
  end
end
