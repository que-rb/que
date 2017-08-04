# frozen_string_literal: true

# Tools for logging from Que.

module Que
  module Utils
    module Middleware
      def run_middleware(job, &block)
        middleware.reverse.inject(block) do |memo, b|
          proc { b.call(job, &memo) }
        end.call
      end

      def middleware
        @middleware ||= []
      end
    end
  end
end
