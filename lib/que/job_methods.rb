# frozen_string_literal: true

module Que
  SQL[:finish_job] =
    %{
      UPDATE public.que_jobs
      SET finished_at = now()
      WHERE id = $1::bigint
    }

  SQL[:expire_job] =
    %{
      UPDATE public.que_jobs
      SET error_count = error_count + 1,
          expired_at = now()
      WHERE id = $1::bigint
    }

  SQL[:destroy_job] =
    %{
      DELETE FROM public.que_jobs
      WHERE id = $1::bigint
    }

  SQL[:set_error] =
    %{
      UPDATE public.que_jobs
      SET error_count          = error_count + 1,
          run_at               = now() + $1::float * '1 second'::interval,
          last_error_message   = left($2::text, 500),
          last_error_backtrace = left($3::text, 10000)
      WHERE id = $4::bigint
    }

  module JobMethods
    # Note that we delegate almost all methods to the result of the que_target
    # method, which could be one of a few things, depending on the circumstance.

    # Run the job with error handling and cleanup logic. Optionally support
    # overriding the args, because it's necessary when jobs are invoked from
    # ActiveJob.
    def _run(args: nil, kwargs: nil, reraise_errors: false)
      if args.nil? && que_target
        args = que_target.que_attrs.fetch(:args)
      end

      if kwargs.nil? && que_target
        kwargs = que_target.que_attrs.fetch(:kwargs)
      end

      run(*args, **kwargs)
      default_resolve_action if que_target && !que_target.que_resolved
    rescue => error
      raise error unless que_target

      que_target.que_error = error

      run_error_notifier =
        begin
          handle_error(error)
        rescue => error_2
          Que.notify_error(error_2, que_target.que_attrs)
          true
        end

      Que.notify_error(error, que_target.que_attrs) if run_error_notifier
      retry_in_default_interval unless que_target.que_resolved

      raise error if reraise_errors
    end

    def log_level(elapsed)
      :debug
    end

    private

    # This method defines the object on which the various job helper methods are
    # acting. When using Que in the default configuration this will just be
    # self, but when using the Que adapter for ActiveJob it'll be the actual
    # underlying job object. When running an ActiveJob::Base subclass that
    # includes this module through a separate adapter this will be nil - hence,
    # the defensive coding in every method that no-ops if que_target is falsy.
    def que_target
      raise NotImplementedError
    end

    def resolve_que_setting(*args)
      return unless que_target

      que_target.class.resolve_que_setting(*args)
    end

    def default_resolve_action
      return unless que_target

      destroy
    end

    def expire
      return unless que_target

      if id = que_target.que_attrs[:id]
        Que.execute :expire_job, [id]
      end

      que_target.que_resolved = true
    end

    def finish
      return unless que_target

      if id = que_target.que_attrs[:id]
        Que.execute :finish_job, [id]
      end

      que_target.que_resolved = true
    end

    def error_count
      return 0 unless que_target

      count = que_target.que_attrs.fetch(:error_count)
      que_target.que_error ? count + 1 : count
    end

    # To be overridden in subclasses.
    def handle_error(error)
      return unless que_target

      max = resolve_que_setting(:maximum_retry_count)

      if max && error_count > max
        expire
      else
        retry_in_default_interval
      end
    end

    def retry_in_default_interval
      return unless que_target

      retry_in(resolve_que_setting(:retry_interval, error_count))
    end

    # Explicitly check for the job id in these helpers, because it won't exist
    # if we're running synchronously.
    def retry_in(period)
      return unless que_target

      if id = que_target.que_attrs[:id]
        values = [period]

        if e = que_target.que_error
          values << "#{e.class}: #{e.message}".slice(0, 500) << e.backtrace.join("\n").slice(0, 10000)
        else
          values << nil << nil
        end

        Que.execute :set_error, values << id
      end

      que_target.que_resolved = true
    end

    def destroy
      return unless que_target

      if id = que_target.que_attrs[:id]
        Que.execute :destroy_job, [id]
      end

      que_target.que_resolved = true
    end
  end
end
