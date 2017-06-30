# frozen_string_literal: true

# An assertion helper, so that error reports will hopefully be of higher
# quality.

module Que
  class AssertionFailed < Error; end

  class << self
    # Want to support:
    #   assert(x)                       # Truthiness.
    #   assert(thing, other)            # Trip-equals.
    #   assert([thing1, thing2], other) # Multiple Trip-equals.

    def assert(*args, &block)
      comparison, truth, pass = check_assertion_args(*args)
      return truth if pass

      message =
        if block_given?
          yield.to_s
        elsif comparison
          "Expected #{comparison.inspect}, got #{truth.inspect}!"
        else
          "Assertion failed!"
        end

      # Remove this method from the backtrace, to make errors clearer.
      raise AssertionFailed, message, caller
    end

    def assert?(*args)
      comparison, truth, pass = check_assertion_args(*args)
      !!pass
    end

    private

    def check_assertion_args(first, second = (second_omitted = true; nil))
      if second_omitted
        comparison = nil
        truth      = first
      else
        comparison = first
        truth      = second
      end

      pass =
        if second_omitted
          truth
        elsif comparison.is_a?(Array)
          comparison.any? { |k| k === truth }
        else
          comparison === truth
        end

      [comparison, truth, pass]
    end
  end
end
