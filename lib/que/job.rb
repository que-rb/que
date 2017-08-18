# frozen_string_literal: true

# The class that jobs should inherit from.

module Que
  class Job
    include JobMethods

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

    SQL[:finish_job] =
      %{
        UPDATE public.que_jobs
        SET finished_at = now()
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
            last_error_message   = $2::text,
            last_error_backtrace = $3::text

        WHERE id = $4::bigint
      }

    attr_reader :que_attrs
    attr_accessor :que_error, :que_resolved

    def initialize(attrs)
      @que_attrs = attrs
      Que.internal_log(:job_instantiate, self) { attrs }
    end

    # Subclasses should define their own run methods, but keep an empty one
    # here so that Que::Job.enqueue can queue an empty job in testing.
    def run(*args)
    end

    private

    def que_target
      self
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
