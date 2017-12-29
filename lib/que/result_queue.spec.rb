# frozen_string_literal: true

require 'spec_helper'

describe Que::ResultQueue do
  let :result_queue do
    Que::ResultQueue.new
  end

  describe "push" do
    it "should add items to the result queue in a thread-safe manner" do
      ids = (1..100).to_a.shuffle
      result_queue # Initialize before it's accessed by different threads.

      threads = ids.each_slice(25).to_a.map do |id_set|
        Thread.new do
          id_set.each do |id|
            result_queue.push(id)
          end
        end
      end

      threads.each(&:join)

      assert_equal (1..100).to_a, result_queue.to_a.sort
    end
  end

  describe "clear" do
    it "should remove and return everything from the result queue" do
      (1..5).each { |i| result_queue.push(i) }

      assert_equal (1..5).to_a, result_queue.clear
      assert_equal [],          result_queue.clear
    end
  end

  describe "to_a" do
    it "should return a copy of the result queue" do
      (1..5).each { |i| result_queue.push(i) }

      assert_equal (1..5).to_a, result_queue.to_a
      assert_equal (1..5).to_a, result_queue.to_a
    end
  end

  describe "length" do
    it "should return the length of the result queue" do
      (1..5).each { |i| result_queue.push(i) }

      assert_equal 5, result_queue.length
    end
  end
end
