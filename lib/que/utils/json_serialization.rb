# frozen_string_literal: true

# Logic for serializing to/from JSON. We assume that the standard library's JSON
# module is good enough for our purposes.

require 'json'

module Que
  module Utils
    module JSONSerialization
      def serialize_json(object)
        JSON.dump(object)
      end

      def deserialize_json(json)
        # Allowing `create_additions` would be a security vulnerability.
        JSON.parse(json, symbolize_names: true, create_additions: false)
      end
    end
  end
end
