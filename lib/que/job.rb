# frozen_string_literal: true

# The class that jobs should inherit from.

module Que
  class Job
    SQL[:insert_job] =
      %{
        INSERT INTO public.que_jobs
        (queue, priority, run_at, job_class, data)
        VALUES
        (
          coalesce($1, '')::text,
          coalesce($2, 100)::smallint,
          coalesce($3, now())::timestamptz,
          $4::text,
          coalesce($5, '{"args":[]}')::jsonb
        )
        RETURNING *
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
            run_at               = now() + $1::bigint * '1 second'::interval,
            last_error_message   = $2::text,
            last_error_backtrace = $3::text

        WHERE id = $4::bigint
      }

    attr_reader :que_attrs, :que_error

    def initialize(attrs)
      @que_attrs = attrs
      Que.internal_log(:job_instantiate, self) { attrs }
    end

    # Subclasses should define their own run methods, but keep an empty one
    # here so that Que::Job.enqueue can queue an empty job in testing.
    def run(*args)
    end

    def _run
      run(*que_attrs.fetch(:data).fetch(:args))
    end

    # Run the job with the error handling and cleaning up that we need when
    # running in a worker. This method is skipped when running synchronously.
    def _run_asynchronously
      _run
      finish unless @que_resolved
    rescue => error
      @que_error = error

      run_error_notifier =
        begin
          handle_error(error)
        rescue => error_2
          Que.notify_error(error_2, que_attrs)
          retry_in_default_interval
        end

      Que.notify_error(error, que_attrs) if run_error_notifier
      finish unless @que_resolved
    end

    private

    def finish
      destroy
    end

    def error_count
      count = que_attrs.fetch(:error_count)
      @que_error ? count + 1 : count
    end

    # To be overridden in subclasses.
    def handle_error(error)
      retry_in_default_interval
    end

    def retry_in_default_interval
      retry_in(resolve_que_setting(:retry_interval, error_count))
    end

    # Explicitly check for the job id in these helpers, because it won't exist
    # if we're doing JobClass.run().
    def retry_in(period)
      if id = que_attrs[:id]
        values = [period]

        if e = que_error
          values << e.message << e.backtrace.join("\n")
        else
          values << nil << nil
        end

        Que.execute :set_error, values << id
      end

      @que_resolved = true
    end

    def destroy
      if id = que_attrs[:id]
        Que.execute :destroy_job, [id]
      end

      @que_resolved = true
    end

    def resolve_que_setting(*args)
      self.class.resolve_que_setting(*args)
    end

    @retry_interval = proc { |count| count ** 4 + 3 }

    class << self
      attr_accessor :run_synchronously

      def enqueue(
        *args,
        queue:     nil,
        priority:  nil,
        run_at:    nil,
        job_class: nil,
        **arg_opts
      )

        args << arg_opts if arg_opts.any?

        attrs = {
          queue:    queue    || resolve_que_setting(:queue) || Que.default_queue,
          priority: priority || resolve_que_setting(:priority),
          run_at:   run_at   || resolve_que_setting(:run_at),
          data:     Que.serialize_json(args: args),
          job_class: \
            job_class || name ||
              raise(Error, "Can't enqueue an anonymous subclass of Que::Job"),
        }

        if attrs[:run_at].nil? && resolve_que_setting(:run_synchronously)
          attrs[:data] = Que.deserialize_json(attrs[:data])
          _run_attrs(attrs)
        else
          values =
            Que.execute(
              :insert_job,
              attrs.values_at(:queue, :priority, :run_at, :job_class, :data),
            ).first

          new(values)
        end
      end

      def run(*args)
        # Make sure things behave the same as they would have with a round-trip
        # to the DB.
        data = Que.deserialize_json(Que.serialize_json(args: args))

        # Should not fail if there's no DB connection.
        _run_attrs(data: data)
      end

      def resolve_que_setting(setting, *args)
        iv_name = :"@#{setting}"

        if instance_variable_defined?(iv_name)
          value = instance_variable_get(iv_name)
          value.respond_to?(:call) ? value.call(*args) : value
        else
          c = superclass
          if c.respond_to?(:resolve_que_setting)
            c.resolve_que_setting(setting, *args)
          end
        end
      end

      private

      def _run_attrs(attrs)
        attrs[:error_count] = 0
        Que.recursively_freeze(attrs)
        job = new(attrs)
        Que.run_middleware(job) { job.tap(&:_run) }
        job
      end
    end
  end
end
