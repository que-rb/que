# frozen_string_literal: true

# The class that most jobs inherit from.

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

    def handle_error(error)
      error_count    = @attrs[:error_count] += 1
      retry_interval = self.class.retry_interval || Job.retry_interval

      wait =
        if retry_interval.respond_to?(:call)
          retry_interval.call(error_count)
        else
          retry_interval
        end

      retry_in(wait)
    end

    def retry_in(period)
      Que.execute :set_error, [period, @_error.message, attrs.fetch(:id)]
      @retried = true
    end

    def destroy
      Que.execute :destroy_job, [attrs.fetch(:id)]
      @destroyed = true
    end

    @retry_interval = proc { |count| count ** 4 + 3 }

    class << self
      attr_reader :retry_interval

      def enqueue(*args, job_class: nil, run_at: nil, priority: nil, **arg_opts)
        args << arg_opts if arg_opts.any?

        attrs = {
          job_class: job_class || to_s,
          args: args,
        }

        if t = run_at || @run_at && @run_at.call
          attrs[:run_at] = t
        end

        if p = priority || @priority
          attrs[:priority] = p
        end

        if Que.mode == :sync && !t
          run(*attrs[:args])
        else
          values =
            Que.execute(
              :insert_job,
              attrs.values_at(:priority, :run_at, :job_class, :args),
            ).first

          new(values)
        end
      end

      def run(*args)
        # Should not fail if there's no DB connection.
        new(args: args).tap { |job| job.run(*args) }
      end
    end
  end
end
