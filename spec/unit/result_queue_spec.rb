# frozen_string_literal: true

require 'spec_helper'

describe Que::ResultQueue do
  let :result_queue do
    Que::ResultQueue.new
  end

  describe "#push and #clear" do
    it "should add items and remove all items from the result queue" do
      ids = (1..100).to_a.shuffle
      result_queue # Initialize before it's accessed by different threads.

      threads = ids.each_slice(25).to_a.map do |id_set|
        Thread.new do
          id_set.each do |id|
            result_queue.push(id)
          end
        end
      end

      threads.each &:join

      assert_equal (1..100).to_a, result_queue.clear.sort
      assert_equal [],            result_queue.clear
    end
  end
end
