require 'spec_helper'

describe Que::JobQueue do
  before do
    @jq = Que::JobQueue.new
  end

  describe "#push" do
    it "should add an item and retain the sort order" do
      @jq.to_a.should == []
      @jq.push 4
      @jq.to_a.should == [4]
      @jq.push 3
      @jq.to_a.should == [3, 4]
      @jq.push 6
      @jq.to_a.should == [3, 4, 6]
      @jq.push 5
      @jq.to_a.should == [3, 4, 5, 6]
      @jq.push 4
      @jq.to_a.should == [3, 4, 4, 5, 6]
    end

    it "should be able to add many items at once" do
      @jq.push 0, 1
      items = (2..10).to_a.shuffle
      @jq.push(items)
      @jq.to_a.should == (0..10).to_a
    end

    describe "when the queue is already at its maximum size" do
      before do
        @jq = Que::JobQueue.new(20)
      end

      it "should trim down to the maximum size by discarding the greatest items" do
        @jq.push (1..21).to_a
        @jq.to_a.should == (1..20).to_a
        @jq.push 0
        @jq.to_a.should == (0..19).to_a
      end
    end
  end

  describe "#shift" do
    it "should return the lowest item by sort order" do
      @jq.push (1..20).to_a
      @jq.shift.should == 1
      @jq.to_a.should == (2..20).to_a
      @jq.shift.should == 2
      @jq.to_a.should == (3..20).to_a
    end

    it "should block for multiple threads when the queue is empty" do
      threads = 4.times.map { Thread.new { Thread.current[:item] = @jq.shift } }

      sleep_until { threads.all? { |t| t.status == 'sleep' } }
      @jq.push (1..4).to_a
      sleep_until { threads.all? { |t| t.status == false } }

      threads.map{|t| t[:item]}.sort.should == (1..4).to_a
    end
  end
end
