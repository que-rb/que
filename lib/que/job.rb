# frozen_string_literal: true

module Que
  class Job
    attr_reader :attrs, :_error

    def initialize(attrs)
      @attrs = attrs
    end

    # Subclasses should define their own run methods, but keep an empty one
    # here so that Que::Job.enqueue can queue an empty job in testing.
    def run(*args)
    end

    def _run
      run(*attrs[:args])
      destroy unless @destroyed
    rescue => error
      @_error = error
      run_error_notifier = handle_error(error)
      destroy unless @retried || @destroyed

      if run_error_notifier && Que.error_notifier
        # Protect the work loop from a failure of the error notifier.
        Que.error_notifier.call(error, @attrs) rescue nil
      end
    end

    private

    def error_count
      @attrs[:error_count]
    end

    def error_message
      self.class.send(:error_message, @_error)
    end

    def handle_error(error)
      error_count = @attrs[:error_count] += 1
      retry_interval = self.class.retry_interval || Job.retry_interval
      wait = retry_interval.respond_to?(:call) ? retry_interval.call(error_count) : retry_interval
      retry_in(wait)
    end

    def retry_in(period)
      Que.execute :set_error, [period, error_message] + @attrs.values_at(:queue, :priority, :run_at, :job_id)
      @retried = true
    end

    def destroy
      Que.execute :destroy_job, attrs.values_at(:queue, :priority, :run_at, :job_id)
      @destroyed = true
    end

    @retry_interval = proc { |count| count ** 4 + 3 }

    class << self
      attr_reader :retry_interval

      def enqueue(*args)
        if args.last.is_a?(Hash)
          options   = args.pop
          queue     = options.delete(:queue) || '' if options.key?(:queue)
          job_class = options.delete(:job_class)
          run_at    = options.delete(:run_at)
          priority  = options.delete(:priority)
          args << options if options.any?
        end

        attrs = {:job_class => job_class || to_s, :args => args}

        warn "@default_run_at in #{to_s} has been deprecated and will be removed in Que version 1.0.0. Please use @run_at instead." if @default_run_at

        if t = run_at || @run_at && @run_at.call || @default_run_at && @default_run_at.call
          attrs[:run_at] = t
        end

        warn "@default_priority in #{to_s} has been deprecated and will be removed in Que version 1.0.0. Please use @priority instead." if @default_priority

        if p = priority || @priority || @default_priority
          attrs[:priority] = p
        end

        if q = queue || @queue
          attrs[:queue] = q
        end

        if Que.mode == :sync && !t
          run(*attrs[:args])
        else
          values = Que.execute(:insert_job, attrs.values_at(:queue, :priority, :run_at, :job_class, :args)).first
          Que.adapter.wake_worker_after_commit unless t
          new(values)
        end
      end

      def queue(*args)
        warn "#{to_s}.queue(*args) is deprecated and will be removed in Que version 1.0.0. Please use #{to_s}.enqueue(*args) instead."
        enqueue(*args)
      end

      def run(*args)
        # Should not fail if there's no DB connection.
        new(:args => args).tap { |job| job.run(*args) }
      end

      def work(queue = '')
        # Since we're taking session-level advisory locks, we have to hold the
        # same connection throughout the process of getting a job, working it,
        # deleting it, and removing the lock.
        return_value =
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
                  instance = klass.new(job)
                  instance._run
                  if e = instance._error
                    {:event => :job_errored, :job => job, :error => e}
                  else
                    {:event => :job_worked, :job => job}
                  end
                end
              else
                {:event => :job_unavailable}
              end
            rescue => error
              begin
                if job
                  count    = job[:error_count].to_i + 1
                  interval = klass && klass.respond_to?(:retry_interval) && klass.retry_interval || retry_interval
                  delay    = interval.respond_to?(:call) ? interval.call(count) : interval
                  message  = error_message(error)
                  Que.execute :set_error, [delay, message] + job.values_at(:queue, :priority, :run_at, :job_id)
                end
              rescue
                # If we can't reach the database for some reason, too bad, but
                # don't let it crash the work loop.
              end

              if Que.error_notifier
                # Similarly, protect the work loop from a failure of the error notifier.
                Que.error_notifier.call(error, job) rescue nil
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

        Que.adapter.cleanup!

        return_value
      end

      private

      def error_message(error)
        message = error.class.to_s

        unless error.message.nil? || error.message.strip.empty?
          message << ": #{error.message}"
        end

        message = message.slice(0, 500)

        ([message] + error.backtrace).join("\n")
      end

      def class_for(string)
        Que.constantize(string)
      end
    end
  end
end
