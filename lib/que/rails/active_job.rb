# frozen_string_literal: true

module Que
  module Rails
    module ActiveJob
      module JobExtensions
        include JobMethods

        def self.included(base)
          base.prepend(PrependedMethods)
        end

        def que_target
          Thread.current[:que_current_job]
        end

        private

        # Filter out :_aj_symbol_keys constructs so that keywords work as
        # expected.
        def que_filter_args(thing)
          case thing
          when Array
            thing.map { |t| que_filter_args(t) }
          when Hash
            h = {}
            thing.each do |k, v|
              h[k] = que_filter_args(v) unless k == :_aj_symbol_keys
            end
            h
          else
            thing
          end
        end

        module PrependedMethods
          def perform(*args)
            if respond_to?(:run)
              _run_asynchronously(
                args: Que.recursively_freeze(que_filter_args(args))
              )
            else
              super
            end
          end
        end
      end

      module WrapperExtensions
        # The Rails adapter (built against a pre-1.0 version of this gem)
        # assumes that it can access a job's id via job.attrs["job_id"]. So,
        # oblige it.
        def attrs
          {"job_id" => que_attrs[:id]}
        end

        # We cast args to symbols, but ActiveJob expects to be able to index
        # into the args with strings, so support that.
        ATTRS_DEFAULT_PROC = -> (hash, key) do
          return unless String === key
          symbol_key = key.to_sym
          # Check for the key's presence first, because if it doesn't exist this
          # proc will just get called again and we'll get a stack overflow.
          hash[symbol_key] if hash.has_key?(symbol_key)
        end

        def run(args)
          # Fix the args hash before it's passed to ActiveJob.
          args = args.dup
          args.default_proc = ATTRS_DEFAULT_PROC

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
            super(args)
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

ActiveJob::QueueAdapters::QueAdapter::JobWrapper.prepend(
  Que::Rails::ActiveJob::WrapperExtensions
)
