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
          coalesce($3, now())::timestamptz,
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
        INSERT INTO public.que_jobs
        (queue, priority, run_at, job_class, args, kwargs, data, job_schema_version)
        SELECT
          coalesce(queue, 'default')::text,
          coalesce(priority, 100)::smallint,
          coalesce(run_at, now())::timestamptz,
          job_class::text,
          coalesce(args, '[]')::jsonb,
          coalesce(kwargs, '{}')::jsonb,
          coalesce(data, '{}')::jsonb,
          #{Que.job_schema_version}
        FROM json_populate_recordset(null::que_jobs, $1)
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

        job_class = job_options[:job_class] || name ||
          raise(Error, "Can't enqueue an anonymous subclass of Que::Job")

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

        if Thread.current[:que_jobs_to_bulk_insert]
          # Don't resolve class settings during `.enqueue`, only resolve them
          # during `._bulk_enqueue_insert` so they can be overwritten by specifying
          # them in `.bulk_enqueue`.
          attrs = {
            queue:     job_options[:queue],
            priority:  job_options[:priority],
            run_at:    job_options[:run_at],
            job_class: job_class == 'Que::Job' ? nil : job_class,
            args:      args,
            kwargs:    kwargs,
            data:      job_options[:tags] && { tags: job_options[:tags] },
            klass:     self,
          }

          Thread.current[:que_jobs_to_bulk_insert][:jobs_attrs] << attrs
          return new({})
        end

        attrs = {
          queue:     job_options[:queue]    || resolve_que_setting(:queue) || Que.default_queue,
          priority:  job_options[:priority] || resolve_que_setting(:priority),
          run_at:    job_options[:run_at]   || resolve_que_setting(:run_at),
          job_class: job_class,
          args:      args,
          kwargs:    kwargs,
          data:      job_options[:tags] ? { tags: job_options[:tags] } : {},
        }

        if attrs[:run_at].nil? && resolve_que_setting(:run_synchronously)
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
        _bulk_enqueue_insert(jobs_attrs, job_options: job_options, notify: notify)
      ensure
        Thread.current[:que_jobs_to_bulk_insert] = nil
      end

      def _bulk_enqueue_insert(jobs_attrs, job_options: {}, notify: false)
        raise 'Unexpected bulk args format' if !jobs_attrs.is_a?(Array) || !jobs_attrs.all? { |a| a.is_a?(Hash) }

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

        jobs_attrs = jobs_attrs.map do |attrs|
          klass = attrs[:klass] || self

          attrs = {
            queue:     attrs[:queue]     || job_options[:queue]     || klass.resolve_que_setting(:queue) || Que.default_queue,
            priority:  attrs[:priority]  || job_options[:priority]  || klass.resolve_que_setting(:priority),
            run_at:    attrs[:run_at]    || job_options[:run_at]    || klass.resolve_que_setting(:run_at),
            job_class: attrs[:job_class] || job_options[:job_class] || klass.name,
            args:      attrs[:args]      || [],
            kwargs:    attrs[:kwargs]    || {},
            data:      attrs[:data]      || (job_options[:tags] ? { tags: job_options[:tags] } : {}),
            klass:     klass
          }

          if attrs[:run_at].nil? && klass.resolve_que_setting(:run_synchronously)
            klass._run_attrs(
              attrs.reject { |k| k == :klass }.merge(
                args: Que.deserialize_json(Que.serialize_json(attrs[:args])),
                kwargs: Que.deserialize_json(Que.serialize_json(attrs[:kwargs])),
                data: Que.deserialize_json(Que.serialize_json(attrs[:data])),
              )
            )
            nil
          else
            attrs
          end
        end.compact

        values_array =
          Que.transaction do
            Que.execute('SET LOCAL que.skip_notify TO true') unless notify
            Que.execute(
              :bulk_insert_jobs,
              [Que.serialize_json(jobs_attrs.map { |attrs| attrs.reject { |k| k == :klass } })]
            )
          end
        values_array.zip(jobs_attrs).map { |values, attrs| attrs.fetch(:klass).new(values) }
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

      protected

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
