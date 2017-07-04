# frozen_string_literal: true

require 'spec_helper'

describe Que do
  def assert_assertion_passes(*args, &block)
    assert_equal true, Que.assert?(*args, &block)

    if (v = args.last).nil?
      assert_nil Que.assert(*args, &block)
    else
      assert_equal v, Que.assert(*args, &block)
    end
  end

  def assert_assertion_fails(*args, &block)
    assert_equal false, Que.assert?(*args, &block)

    assert_raises Que::AssertionFailed do
      Que.assert(*args, &block)
    end
  end

  it "should handle failures without a block" do
    error = assert_assertion_fails(false)

    assert_equal "Assertion failed!", error.message
    assert_match /lib\/que\/assertions.spec.rb:20/, error.backtrace.first
  end

  it "should handle failures with a block" do
    error = assert_assertion_fails(false) { "custom message!" }

    assert_equal "custom message!", error.message
    assert_match /lib\/que\/assertions.spec.rb:20/, error.backtrace.first
  end

  it "should return the argument if it is truthy" do
    called = false

    assert_assertion_passes(5)   { called = true; "Expected 5" }
    assert_assertion_passes('F') { called = true; "Expected F" }

    assert_equal false, called
  end

  it "should return the second arg if first arg === second arg" do
    called = false

    assert_assertion_passes(Integer, 5)    { called = true; "Custom!" }
    assert_assertion_passes(String, 'F')   { called = true; "Custom!" }
    assert_assertion_passes(NilClass, nil) { called = true; "Custom!" }

    assert_equal false, called
  end

  it "should raise an error unless first arg === second arg" do
    error = assert_assertion_fails(Integer, 'string')
    assert_equal "Expected Integer, got \"string\"!", error.message

    error = assert_assertion_fails(String, 5)
    assert_equal "Expected String, got 5!", error.message
  end

  it "should support an array as the first argument" do
    assert_assertion_passes([TrueClass, FalseClass], true)
    assert_assertion_passes([TrueClass, FalseClass], false)
    assert_assertion_passes([/abc/, /erre/], 'ferret')

    error = assert_assertion_fails([/ERRE/, /ErRe/], 'ferret')
    assert_equal "Expected [/ERRE/, /ErRe/], got \"ferret\"!", error.message
  end
end
