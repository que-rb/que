# frozen_string_literal: true

# Assertion helpers. Que has a fair amount of internal state, and there's no
# telling what users will try to throw at it, so for ease of debugging issues it
# makes sense to sanity-check frequently.

module Que
  module Utils
    module Assertions
      class AssertionFailed < Error; end

      def assert(*args, &block)
        comparison, object, pass = _check_assertion_args(*args)
        return object if pass

        message =
          if block_given?
            yield.to_s
          elsif comparison
            "Expected #{comparison.inspect}, got #{object.inspect}!"
          else
            "Assertion failed!"
          end

        # Remove this method from the backtrace, to make errors clearer.
        raise AssertionFailed, message, caller
      end

      def assert?(*args)
        _, _, pass = _check_assertion_args(*args)
        !!pass
      end

      private

      # Want to support:
      #   assert(x)                       # Truthiness.
      #   assert(thing, other)            # Trip-equals.
      #   assert([thing1, thing2], other) # Multiple Trip-equals.
      def _check_assertion_args(first, second = (second_omitted = true; nil))
        if second_omitted
          comparison = nil
          object     = first
        else
          comparison = first
          object     = second
        end

        pass =
          if second_omitted
            object
          elsif comparison.is_a?(Array)
            comparison.any? { |k| k === object }
          else
            comparison === object
          end

        [comparison, object, pass]
      end
    end
  end
end
