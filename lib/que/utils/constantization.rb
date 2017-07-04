# frozen_string_literal: true

module Que
  module Utils
    module Constantization
      def constantize(string)
        assert String, string

        if string.respond_to?(:constantize)
          string.constantize
        else
          names = string.split('::')
          names.reject!(&:empty?)
          names.inject(Object, &:const_get)
        end
      end
    end
  end
end
