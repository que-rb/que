# frozen_string_literal: true

# The class that jobs should generally inherit from.

module Que
  class Job
    include JobMethods

    MAXIMUM_TAGS_COUNT = 5
    MAXIMUM_TAG_LENGTH = 100

    SQL[:insert_job] =
      %{
        INSERT INTO public.que_jobs
        (queue, priority, run_at, job_class, args, kwargs, data, job_schema_version)
        VALUES
        (
          coalesce($1, 'default')::text,
          coalesce($2, 100)::smallint,
          greatest($3, now())::timestamptz,
          $4::text,
          coalesce($5, '[]')::jsonb,
          coalesce($6, '{}')::jsonb,
          coalesce($7, '{}')::jsonb,
          #{Que.job_schema_version}
        )
        RETURNING *
      }

    SQL[:bulk_insert_jobs] =
      %{
        WITH args_and_kwargs as (
          SELECT * from json_to_recordset(coalesce($5, '[{args:{},kwargs:{}}]')::json) as x(args jsonb, kwargs jsonb)
        )
        INSERT INTO public.que_jobs
        (queue, priority, run_at, job_class, args, kwargs, data, job_schema_version)
        SELECT
          coalesce($1, 'default')::text,
          coalesce($2, 100)::smallint,
          greatest($3, now())::timestamptz,
          $4::text,
          args_and_kwargs.args,
          args_and_kwargs.kwargs,
          coalesce($6, '{}')::jsonb,
          #{Que.job_schema_version}
        FROM args_and_kwargs
        RETURNING *
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

    # Have the job helper methods act on this object.
    def que_target
      self
    end

    class << self
      # Job class configuration options.
      attr_accessor \
        :run_synchronously,
        :retry_interval,
        :maximum_retry_count,
        :queue,
        :priority,
        :run_at

      def enqueue(*args)
        args, kwargs = Que.split_out_ruby2_keywords(args)

        job_options = kwargs.delete(:job_options) || {}

        if job_options[:tags]
          if job_options[:tags].length > MAXIMUM_TAGS_COUNT
            raise Que::Error, "Can't enqueue a job with more than #{MAXIMUM_TAGS_COUNT} tags! (passed #{job_options[:tags].length})"
          end

          job_options[:tags].each do |tag|
            if tag.length > MAXIMUM_TAG_LENGTH
              raise Que::Error, "Can't enqueue a job with a tag longer than 100 characters! (\"#{tag}\")"
            end
          end
        end

        attrs = {
          queue:    job_options[:queue]    || resolve_que_setting(:queue) || Que.default_queue,
          priority: job_options[:priority] || resolve_que_setting(:priority),
          run_at:   job_options[:run_at]   || resolve_que_setting(:run_at),
          args:     args,
          kwargs:   kwargs,
          data:     job_options[:tags] ? { tags: job_options[:tags] } : {},
          job_class: \
            job_options[:job_class] || name ||
              raise(Error, "Can't enqueue an anonymous subclass of Que::Job"),
        }

        if Thread.current[:que_jobs_to_bulk_insert]
          if self.name == 'ActiveJob::QueueAdapters::QueAdapter::JobWrapper'
            raise Que::Error, "Que.bulk_enqueue does not support ActiveJob."
          end

          raise Que::Error, "When using .bulk_enqueue, job_options must be passed to that method rather than .enqueue" unless job_options == {}

          Thread.current[:que_jobs_to_bulk_insert][:jobs_attrs] << attrs
          new({})
        elsif attrs[:run_at].nil? && resolve_que_setting(:run_synchronously)
          attrs.merge!(
            args: Que.deserialize_json(Que.serialize_json(attrs[:args])),
            kwargs: Que.deserialize_json(Que.serialize_json(attrs[:kwargs])),
            data: Que.deserialize_json(Que.serialize_json(attrs[:data])),
          )
          _run_attrs(attrs)
        else
          attrs.merge!(
            args: Que.serialize_json(attrs[:args]),
            kwargs: Que.serialize_json(attrs[:kwargs]),
            data: Que.serialize_json(attrs[:data]),
          )
          values = Que.execute(
            :insert_job,
            attrs.values_at(:queue, :priority, :run_at, :job_class, :args, :kwargs, :data),
          ).first
          new(values)
        end
      end
      ruby2_keywords(:enqueue) if respond_to?(:ruby2_keywords, true)

      def bulk_enqueue(job_options: {}, notify: false)
        raise Que::Error, "Can't nest .bulk_enqueue" unless Thread.current[:que_jobs_to_bulk_insert].nil?
        Thread.current[:que_jobs_to_bulk_insert] = { jobs_attrs: [], job_options: job_options }
        yield
        jobs_attrs = Thread.current[:que_jobs_to_bulk_insert][:jobs_attrs]
        job_options = Thread.current[:que_jobs_to_bulk_insert][:job_options]
        return [] if jobs_attrs.empty?
        raise Que::Error, "When using .bulk_enqueue, all jobs enqueued must be of the same job class" unless jobs_attrs.map { |attrs| attrs[:job_class] }.uniq.one?
        args_and_kwargs_array = jobs_attrs.map { |attrs| attrs.slice(:args, :kwargs) }
        klass = job_options[:job_class] ? Que::Job : Que.constantize(jobs_attrs.first[:job_class])
        klass._bulk_enqueue_insert(args_and_kwargs_array, job_options: job_options, notify: notify)
      ensure
        Thread.current[:que_jobs_to_bulk_insert] = nil
      end

      def _bulk_enqueue_insert(args_and_kwargs_array, job_options: {}, notify:)
        raise 'Unexpected bulk args format' if !args_and_kwargs_array.is_a?(Array) || !args_and_kwargs_array.all? { |a| a.is_a?(Hash) }

        if job_options[:tags]
          if job_options[:tags].length > MAXIMUM_TAGS_COUNT
            raise Que::Error, "Can't enqueue a job with more than #{MAXIMUM_TAGS_COUNT} tags! (passed #{job_options[:tags].length})"
          end

          job_options[:tags].each do |tag|
            if tag.length > MAXIMUM_TAG_LENGTH
              raise Que::Error, "Can't enqueue a job with a tag longer than 100 characters! (\"#{tag}\")"
            end
          end
        end

        args_and_kwargs_array = args_and_kwargs_array.map do |args_and_kwargs|
          args_and_kwargs.merge(
            args: args_and_kwargs.fetch(:args, []),
            kwargs: args_and_kwargs.fetch(:kwargs, {}),
          )
        end

        attrs = {
          queue:    job_options[:queue]    || resolve_que_setting(:queue) || Que.default_queue,
          priority: job_options[:priority] || resolve_que_setting(:priority),
          run_at:   job_options[:run_at]   || resolve_que_setting(:run_at),
          args_and_kwargs_array: args_and_kwargs_array,
          data:     job_options[:tags] ? { tags: job_options[:tags] } : {},
          job_class: \
            job_options[:job_class] || name ||
              raise(Error, "Can't enqueue an anonymous subclass of Que::Job"),
        }

        if attrs[:run_at].nil? && resolve_que_setting(:run_synchronously)
          args_and_kwargs_array = Que.deserialize_json(Que.serialize_json(attrs.delete(:args_and_kwargs_array)))
          args_and_kwargs_array.map do |args_and_kwargs|
            _run_attrs(
              attrs.merge(
                args: args_and_kwargs.fetch(:args),
                kwargs: args_and_kwargs.fetch(:kwargs),
              ),
            )
          end
        else
          attrs.merge!(
            args_and_kwargs_array: Que.serialize_json(attrs[:args_and_kwargs_array]),
            data: Que.serialize_json(attrs[:data]),
          )
          values_array =
            Que.transaction do
              Que.execute('SET LOCAL que.skip_notify TO true') unless notify
              Que.execute(
                :bulk_insert_jobs,
                attrs.values_at(:queue, :priority, :run_at, :job_class, :args_and_kwargs_array, :data),
              )
            end
          values_array.map(&method(:new))
        end
      end

      def run(*args)
        # Make sure things behave the same as they would have with a round-trip
        # to the DB.
        args, kwargs = Que.split_out_ruby2_keywords(args)
        args = Que.deserialize_json(Que.serialize_json(args))
        kwargs = Que.deserialize_json(Que.serialize_json(kwargs))

        # Should not fail if there's no DB connection.
        _run_attrs(args: args, kwargs: kwargs)
      end
      ruby2_keywords(:run) if respond_to?(:ruby2_keywords, true)

      def resolve_que_setting(setting, *args)
        value = send(setting) if respond_to?(setting)

        if !value.nil?
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

        new(attrs).tap do |job|
          Que.run_job_middleware(job) do
            job._run(reraise_errors: true)
          end
        end
      end
    end

    # Set up some defaults.
    self.retry_interval      = proc { |count| count ** 4 + 3 }
    self.maximum_retry_count = 15
  end
end
