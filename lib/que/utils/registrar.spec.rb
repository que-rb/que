# frozen_string_literal: true

require 'spec_helper'

describe Que::Utils::Registrar do
  describe "[]" do
    it "should return the value, if it exists" do
      r = Que::Utils::Registrar.new
      r[:blah] = 'value!'
      assert_equal 'value!', r[:blah]
    end

    it "should possibly raise an error if the value doesn't exist" do
      r = Que::Utils::Registrar.new
      error = assert_raises(Que::Error) { r[:blah] }
      assert_equal "value for :blah not found", error.message

      r = Que::Utils::Registrar.new(raise_on_missing: false)
      assert_nil r[:blah]
    end
  end

  describe "[]=" do
    it "should invoke the callback, if any" do
      r = Que::Utils::Registrar.new { |s| s.strip.freeze }
      r[:blah] = "  herherhe  ".dup
      assert_equal "herherhe", r[:blah]
      assert r[:blah].frozen?
    end

    it "should raise an error if the key already exists" do
      r = Que::Utils::Registrar.new
      r[:blah] = 1
      error = assert_raises(Que::Error) { r[:blah] = 2 }
      assert_equal "duplicate value for :blah", error.message
    end
  end
end
