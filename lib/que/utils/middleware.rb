# frozen_string_literal: true

# Logic for middleware to wrap jobs.

module Que
  module Utils
    module Middleware
      def run_middleware(job, &block)
        invoke_middleware(
          middleware: middleware.dup,
          job:        job,
          block:      block,
        )
      end

      def middleware
        @middleware ||= []
      end

      private

      def invoke_middleware(middleware:, job:, block:)
        if m = middleware.shift
          m.call(job) do
            invoke_middleware(middleware: middleware, job: job, block: block)
          end
        else
          block.call
        end
      end
    end
  end
end
