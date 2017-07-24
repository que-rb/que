# frozen_string_literal: true

require 'spec_helper'

describe Que::Utils::Registrar do
  describe "[]" do
    it "should return the value, if it exists"

    it "should raise an error if the value doesn't exist"
  end

  describe "[]=" do
    it "should invoke the callback, if any"

    it "should raise an error if the key already exists"
  end
end
