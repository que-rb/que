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

          def run_#{type}_middleware(item)
            m = #{type}_middleware

            if m.empty?
              yield
            else
              invoke_middleware(middleware: m.dup, item: item) { yield }
            end
          end
        CODE
      end

      private

      def invoke_middleware(middleware:, item:)
        if m = middleware.shift
          m.call(item) do
            invoke_middleware(middleware: middleware, item: item) { yield }
          end
        else
          yield
        end
      end
    end
  end
end
