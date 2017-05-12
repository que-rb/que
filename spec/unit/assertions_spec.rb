# frozen_string_literal: true

require 'spec_helper'

describe Que do
  describe ".assert" do
    it "should handle failures without a block" do
      error =
        assert_raises Que::AssertionFailed do
          Que.assert(false)
        end

      assert_equal "Assertion failed!", error.message
      assert_match /spec\/unit\/assertions_spec.rb:10/, error.backtrace.first
    end

    it "should handle failures with a block" do
      error =
        assert_raises Que::AssertionFailed do
          Que.assert(false) { "custom message!" }
        end

      assert_equal "custom message!", error.message
      assert_match /spec\/unit\/assertions_spec.rb:20/, error.backtrace.first
    end

    it "should return the argument if it is truthy" do
      called = false

      assert_equal 5, Que.assert(5)
      assert_equal 5, Que.assert(5) { called = true; "Expected 5" }

      assert_equal 'F', Que.assert('F')
      assert_equal 'F', Que.assert('F') { called = true; "Expected F" }

      assert_equal false, called
    end

    it "should return the second arg if first arg === second arg" do
      called = false

      assert_equal 5, Que.assert(Integer, 5)
      assert_equal 5, Que.assert(Integer, 5) { called = true; "Custom!" }

      assert_equal 'F', Que.assert(String, 'F')
      assert_equal 'F', Que.assert(String, 'F') { called = true; "Custom!" }

      assert_nil Que.assert(NilClass, nil)
      assert_nil Que.assert(NilClass, nil) { called = true; "Custom!" }

      assert_equal false, called
    end

    it "should support an array as a first argument" do
      assert_equal true,     Que.assert([TrueClass, FalseClass], true)
      assert_equal false,    Que.assert([TrueClass, FalseClass], false)
      assert_equal 'ferret', Que.assert([/erre/], 'ferret')

      error =
        assert_raises Que::AssertionFailed do
          Que.assert([/ERRE/, /ErRe/], 'ferret')
        end

      assert_equal "Expected [/ERRE/, /ErRe/], got \"ferret\"!", error.message
    end

    it "should raise an error unless first arg === second arg" do
      error =
        assert_raises Que::AssertionFailed do
          Que.assert(Integer, 'string')
        end

      assert_equal "Expected Integer, got \"string\"!", error.message

      error =
        assert_raises Que::AssertionFailed do
          Que.assert(String, 5)
        end

      assert_equal "Expected String, got 5!", error.message
    end
  end
end
