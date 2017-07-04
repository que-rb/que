# frozen_string_literal: true

module Que
  module Utils
    module JSONSerialization
      def serialize_json(object)
        JSON.dump(object)
      end

      def deserialize_json(json)
        JSON.parse(json, symbolize_names: true, create_additions: false)
      end
    end
  end
end
