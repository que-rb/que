# frozen_string_literal: true

module Que
  module Utils
    module Constantization
      attr_writer :constantizer

      def constantizer
        @constantizer ||=
          -> (string) { string.split('::').inject(Object, &:const_get) }
      end
    end
  end
end
