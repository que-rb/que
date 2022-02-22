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
        (queue, priority, run_at, job_class, args, data, que_version)
        VALUES
        (
          coalesce($1, 'default')::text,
          coalesce($2, 100)::smallint,
          coalesce($3, now())::timestamptz,
          $4::text,
          coalesce($5, '[]')::jsonb,
          coalesce($6, '{}')::jsonb,
          1
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

      def enqueue(
        *args,
        job_options: {},
        **arg_opts
      )
        arg_opts, job_options = _extract_job_options(arg_opts, job_options.dup)
        args << arg_opts if arg_opts.any?

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
          data:     job_options[:tags] ? Que.serialize_json(tags: job_options[:tags]) : "{}",
          job_class: \
            job_options[:job_class] || name ||
              raise(Error, "Can't enqueue an anonymous subclass of Que::Job"),
        }

        if attrs[:run_at].nil? && resolve_que_setting(:run_synchronously)
          attrs[:args] = Que.deserialize_json(attrs[:args])
          attrs[:data] = Que.deserialize_json(attrs[:data])
          _run_attrs(attrs)
        else
          values =
            Que.execute(
              :insert_job,
              attrs.values_at(:queue, :priority, :run_at, :job_class, :args, :data),
            ).first

          new(values)
        end
      end

      def run(*args)
        # Make sure things behave the same as they would have with a round-trip
        # to the DB.
        args = Que.deserialize_json(Que.serialize_json(args))

        # Should not fail if there's no DB connection.
        _run_attrs(args: args)
      end

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

      def _extract_job_options(arg_opts, job_options)
        deprecated_job_option_names = []

        %i[queue priority run_at job_class tags].each do |option_name|
          next unless arg_opts.key?(option_name) && job_options[option_name].nil?

          job_options[option_name] = arg_opts.delete(option_name)
          deprecated_job_option_names << option_name
        end

        _log_job_options_deprecation(deprecated_job_option_names)

        [arg_opts, job_options]
      end

      def _log_job_options_deprecation(deprecated_job_option_names)
        return unless deprecated_job_option_names.any?

        warn "Passing job options like (#{deprecated_job_option_names.join(', ')}) to `JobClass.enqueue` as top level keyword args has been deprecated and will be removed in version 2.0. Please wrap job options in an explicit `job_options` keyword arg instead."
      end
    end

    # Set up some defaults.
    self.retry_interval      = proc { |count| count ** 4 + 3 }
    self.maximum_retry_count = 15
  end
end
