require 'spec_helper'

describe Que::SortedQueue do
  before do
    @sq = Que::SortedQueue.new
  end

  describe "#insert" do
    it "should add an item and retain the sort order" do
      @sq.to_a.should == []
      @sq.insert 4
      @sq.to_a.should == [4]
      @sq.insert 3
      @sq.to_a.should == [3, 4]
      @sq.insert 6
      @sq.to_a.should == [3, 4, 6]
      @sq.insert 5
      @sq.to_a.should == [3, 4, 5, 6]
      @sq.insert 4
      @sq.to_a.should == [3, 4, 4, 5, 6]
    end

    it "should be able to add many items at once" do
      @sq.insert 0, 1
      items = (2..10).to_a.shuffle
      @sq.insert(items)
      @sq.to_a.should == (0..10).to_a
    end

    describe "when the queue is already at its maximum size" do
      before do
        @sq = Que::SortedQueue.new(20)
      end

      it "should trim down to the maximum size by discarding the greatest items" do
        @sq.insert (1..21).to_a
        @sq.to_a.should == (1..20).to_a
        @sq.insert 0
        @sq.to_a.should == (0..19).to_a
      end
    end
  end

  describe "#shift" do
    it "should return the lowest item by sort order" do
      @sq.insert (1..20).to_a
      @sq.shift.should == 1
      @sq.to_a.should == (2..20).to_a
      @sq.shift.should == 2
      @sq.to_a.should == (3..20).to_a
    end

    it "should block for multiple threads when the queue is empty" do
      threads = 4.times.map { Thread.new { Thread.current[:item] = @sq.shift } }

      sleep_until { threads.all? { |t| t.status == 'sleep' } }
      @sq.insert (1..4).to_a
      sleep_until { threads.all? { |t| t.status == false } }

      threads.map{|t| t[:item]}.sort.should == (1..4).to_a
    end
  end
end
