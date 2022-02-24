# frozen_string_literal: true

# Temporary module allowing ruby2 keyword args to be extracted from an *args splat
# Allows us to ensure consistent behaviour when running on ruby 2 vs ruby 3
# We can remove this if/when we drop support for ruby 2

require 'json'

module Que
  module Utils
    module Ruby2Keywords
      def split_out_ruby2_keywords(args)
        return [args, {}] unless args.last&.is_a?(Hash) && Hash.ruby2_keywords_hash?(args.last)

        [args[0..-2], args.last]
      end
    end
  end
end
