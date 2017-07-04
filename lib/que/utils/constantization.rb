# frozen_string_literal: true

module Que
  module Utils
    module Constantization
      def constantize(string)
        assert String, string

        if string.respond_to?(:constantize)
          string.constantize
        else
          string.split('::').inject(Object, &:const_get)
        end
      end
    end
  end
end
