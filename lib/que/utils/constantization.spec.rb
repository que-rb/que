# frozen_string_literal: true

require 'spec_helper'

describe Que::Utils::Constantization do
  describe "constantize" do
    it "should defer to String#constantize if it exists"

    it "should fallback to custom constant lookup if necessary"
  end

  describe "constantizer=" do
    it "should accept a proc to set the constantization logic"

    it "should accept nil to use the default behavior"
  end
end
