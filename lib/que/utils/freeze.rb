# frozen_string_literal: true

# Tools for introspecting the state of the job queue.

module Que
  module Utils
    module Freeze
      def recursively_freeze(thing)
        case thing
        when Array
          thing.each do |element|
            recursively_freeze(element)
          end
        when Hash
          thing.each do |key, value|
            recursively_freeze(key)
            recursively_freeze(value)
          end
        end

        thing.freeze
      end
    end
  end
end
