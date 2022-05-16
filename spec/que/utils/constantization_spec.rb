# frozen_string_literal: true

require 'spec_helper'

describe Que::Utils::Constantization do
  describe "constantize" do
    def assert_constantization(expected, string)
      actual = Que.constantize(string)
      assert_equal expected, actual
    end

    if !defined?(ActiveRecord)
      # This spec, which defines and undefines String#constantize, might mess up
      # ActiveRecord's internals, so let's skip it.

      it "should defer to String#constantize if it exists" do
        refute ''.respond_to?(:constantize)

        begin
          class String
            def constantize
              Que::Utils
            end
          end

          assert_constantization Que::Utils, ""
        ensure
          class String
            remove_method :constantize
          end

          refute ''.respond_to?(:constantize)
        end
      end
    end

    it "should fallback to custom constant lookup if necessary" do
      assert_constantization \
        Que::Utils::Constantization,
        'Que::Utils::Constantization'

      assert_constantization \
        Que::Utils::Constantization,
        '::Que::Utils::Constantization'
    end
  end
end
