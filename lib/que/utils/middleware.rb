# frozen_string_literal: true

# Logic for middleware to wrap jobs.

module Que
  module Utils
    module Middleware
      TYPES = [
        :job,
        :sql,
      ].freeze

      TYPES.each do |type|
        module_eval <<-CODE
          def #{type}_middleware
            @#{type}_middleware ||= []
          end

          def run_#{type}_middleware(*args)
            m = #{type}_middleware

            if m.empty?
              yield
            else
              invoke_middleware(middleware: m.dup, args: args) { yield }
            end
          end
        CODE
      end

      private

      def invoke_middleware(middleware:, args:)
        if m = middleware.shift
          r = nil
          m.call(*args) do
            r = invoke_middleware(middleware: middleware, args: args) { yield }
          end
          r
        else
          yield
        end
      end
    end
  end
end
