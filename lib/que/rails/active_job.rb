# frozen_string_literal: true

module Que
  module Rails
    module ActiveJob
      module Extensions
        # The Rails adapter (built against a pre-1.0 version of this gem)
        # assumes that it can access a job's id via job.attrs["job_id"]. So,
        # oblige it.
        def attrs
          {"job_id" => que_attrs[:id]}
        end

        ATTRS_DEFAULT_PROC = -> (hash, key) do
          return unless String === key
          symbol_key = key.to_sym
          # Check for the key's presence first, because if it doesn't exist this
          # proc will just get called again and we'll get a stack overflow.
          hash[symbol_key] if hash.has_key?(symbol_key)
        end

        def run(args)
          args = args.dup
          args.default_proc = ATTRS_DEFAULT_PROC
          super(args)
        end
      end
    end
  end
end

ActiveJob::QueueAdapters::QueAdapter::JobWrapper.prepend(Que::Rails::ActiveJob::Extensions)
