# frozen_string_literal: true

# A generic class for registering callbacks/rules/SQL statements/whatever else.
# Basically a hash with a couple extra features for safety.

module Que
  module Utils
    class Registrar
      def initialize(raise_on_missing: true, &block)
        @objects          = {}
        @block            = block
        @raise_on_missing = raise_on_missing
      end

      def [](name)
        @objects.fetch(name) do
          if @raise_on_missing
            raise Error, "value for #{name.inspect} not found"
          end
        end
      end

      def []=(name, value)
        if @objects.has_key?(name)
          raise Error, "duplicate value for #{name.inspect}"
        end

        value = @block.call(value) if @block
        @objects[name] = value
      end
    end
  end
end
