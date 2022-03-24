# frozen_string_literal: true

module Que
  module ActiveJob
    # A module that devs can include into their ApplicationJob classes to get
    # access to Que-like job behavior.
    module JobExtensions
      include JobMethods

      def run(*args)
        raise Error, "Job class #{self.class} didn't define a run() method!"
      end

      def perform(*args)
        args, kwargs = Que.split_out_ruby2_keywords(args)

        Que.internal_log(:active_job_perform, self) do
          {args: args, kwargs: kwargs}
        end

        _run(
          args: Que.recursively_freeze(
            que_filter_args(
              args.map { |a| a.is_a?(Hash) ? a.deep_symbolize_keys : a }
            )
          ),
          kwargs: Que.recursively_freeze(
            que_filter_args(
              kwargs.deep_symbolize_keys,
            )
          ),
        )
      end

      private

      # Have helper methods like `destroy` and `retry_in` delegate to the actual
      # job object. If the current job is being run through an ActiveJob adapter
      # other than Que's, this will return nil, which is fine.
      def que_target
        Thread.current[:que_current_job]
      end

      # Filter out :_aj_symbol_keys constructs so that keywords work as
      # expected.
      def que_filter_args(thing)
        case thing
        when Array
          thing.map { |t| que_filter_args(t) }
        when Hash
          thing.each_with_object({}) do |(k, v), hash|
            hash[k] = que_filter_args(v) unless k == :_aj_symbol_keys
          end
        else
          thing
        end
      end
    end

    # A module that we mix into ActiveJob's wrapper for Que::Job, to maintain
    # backwards-compatibility with internal changes we make.
    module WrapperExtensions
      module ClassMethods
        # We've dropped support for job options supplied as top-level keywords, but ActiveJob's QueAdapter still uses them. So we have to move them into the job_options hash ourselves.
        def enqueue(args, priority:, queue:, run_at: nil)
          super(args, job_options: { priority: priority, queue: queue, run_at: run_at })
        end
      end

      module InstanceMethods
        # The Rails adapter (built against a pre-1.0 version of this gem)
        # assumes that it can access a job's id via job.attrs["job_id"]. So,
        # oblige it.
        def attrs
          {"job_id" => que_attrs[:id]}
        end

        def run(args)
          # Our ActiveJob extensions expect to be able to operate on the actual
          # job object, but there's no way to access it through ActiveJob. So,
          # scope it to the current thread. It's a bit messy, but it's the best
          # option under the circumstances (doesn't require hacking ActiveJob in
          # any more extensive way).

          # There's no reason this logic should ever nest, because it wouldn't
          # make sense to run a worker inside of a job, but even so, assert that
          # nothing absurd is going on.
          Que.assert NilClass, Thread.current[:que_current_job]

          begin
            Thread.current[:que_current_job] = self

            # We symbolize the args hash but ActiveJob doesn't like that :/
            super(args.deep_stringify_keys)
          ensure
            # Also assert that the current job state was only removed now, but
            # unset the job first so that an assertion failure doesn't mess up
            # the state any more than it already has.
            current = Thread.current[:que_current_job]
            Thread.current[:que_current_job] = nil
            Que.assert(self, current)
          end
        end
      end
    end
  end
end

class ActiveJob::QueueAdapters::QueAdapter
  class JobWrapper < Que::Job
    extend Que::ActiveJob::WrapperExtensions::ClassMethods
    prepend Que::ActiveJob::WrapperExtensions::InstanceMethods
  end
end
