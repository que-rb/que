# frozen_string_literal: true

# Tools for introspecting the state of the job queue.

module Que
  module Utils
    module Freeze
      def recursively_freeze(thing)
        case thing
        when Array
          thing.each { |e| recursively_freeze(e) }
        when Hash
          thing.each { |k, v| recursively_freeze(k); recursively_freeze(v) }
        end

        thing.freeze
      end
    end
  end
end
