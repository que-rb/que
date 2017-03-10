# frozen_string_literal: true

require 'spec_helper'

describe Que::ResultQueue do
  before do
    @rq = Que::ResultQueue.new
  end

  describe "#push and #clear" do
    it "should add items and remove all items from the result queue" do
      ids = (1..100).to_a.shuffle

      threads = ids.each_slice(25).to_a.map do |id_set|
        Thread.new do
          id_set.each do |id|
            @rq.push(id)
          end
        end
      end

      threads.each &:join

      assert_equal (1..100).to_a, @rq.clear.sort
      assert_equal [], @rq.clear
    end
  end
end
