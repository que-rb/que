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
          args:     Que.serialize_json(args),
          kwargs:   Que.serialize_json(kwargs),
          data:     job_options[:tags] ? Que.serialize_json(tags: job_options[:tags]) : "{}",
          job_class: \
            job_options[:job_class] || name ||
              raise(Error, "Can't enqueue an anonymous subclass of Que::Job"),
        }

        if attrs[:run_at].nil? && resolve_que_setting(:run_synchronously)
          attrs[:args] = Que.deserialize_json(attrs[:args])
          attrs[:kwargs] = Que.deserialize_json(attrs[:kwargs])
          attrs[:data] = Que.deserialize_json(attrs[:data])
          _run_attrs(attrs)
        else
          values =
            Que.execute(
              :insert_job,
              attrs.values_at(:queue, :priority, :run_at, :job_class, :args, :kwargs, :data),
            ).first
          new(values)
        end
      end
      ruby2_keywords(:enqueue) if respond_to?(:ruby2_keywords, true)

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
