require 'spec_helper'

describe Que::PriorityQueue do
  before do
    @pq = Que::PriorityQueue.new :maximum_size => 8

    @older = Time.now - 50
    @newer = Time.now

    @array = [
      [1, @older, 1],
      [1, @older, 2],
      [1, @newer, 3],
      [1, @newer, 4],
      [2, @older, 5],
      [2, @older, 6],
      [2, @newer, 7],
      [2, @newer, 8]
    ]
  end

  describe "#push" do
    it "should add an item and retain the sort order" do
      ids = []
      @array.shuffle.each do |job|
        @pq.push(job).should be nil
        ids << job[-1]
        @pq.to_a.map{|j| j[-1]}.should == ids.sort
      end
    end

    it "should be able to add many items at once" do
      @pq.push(*@array.shuffle).should be nil
      @pq.to_a.should == @array
    end

    it "when the max is reached should pop the least important jobs and return their ids to be unlocked" do
      @pq.push(*@array)
      @pq.push(@array[0]).should == [@array[7]]
      @pq.push(*@array[1..2]).sort.should == @array[5..6]
      @pq.size.should == 8

      # Make sure pushing multiple items that cross the threshold works properly.
      @pq.clear
      @pq.push(*@array)
      @pq.shift.should == @array[0]
      @pq.push(*@array[0..1]).should == [@array[7]]
      @pq.size.should == 8

      # Pushing very low priority jobs shouldn't happen, since we use
      # #accept? to prevent unnecessary locking, but just in case:
      v = [100, Time.now, 45]
      @pq.push(v).should == [v]
      @pq.to_a.map(&:first).should_not include 100
      @pq.size.should == 8
    end
  end

  describe "#accept?" do
    before do
      @pq.push *@array
    end

    it "should return true if there is sufficient room in the queue" do
      @pq.shift.should == @array[0]
      @pq.size.should be 7
      @pq.accept?(@array[-1]).should be true
    end

    it "should return true if there is insufficient room in the queue, but the pk can knock out a lower-priority job" do
      @pq.accept?(@array[0]).should be true
    end

    it "should return false if there is insufficient room in the queue, and the job's priority is lower than any in the queue" do
      @pq.accept?(@array[-1]).should be false
    end
  end

  describe "#shift" do
    it "should return the lowest item by sort order" do
      @pq.push *@array
      @pq.shift.should == @array[0]
      @pq.to_a.should  == @array[1..7]
      @pq.shift.should == @array[1]
      @pq.to_a.should  == @array[2..7]
    end

    it "should block for multiple threads when the queue is empty" do
      threads = 4.times.map { Thread.new { Thread.current[:id] = @pq.shift } }

      sleep_until { threads.all? { |t| t.status == 'sleep' } }
      @pq.push *@array
      sleep_until { threads.all? { |t| t.status == false } }

      threads.map{|t| t[:id][-1]}.sort.should == (1..4).to_a
    end

    it "should accept a priority value and only accept jobs of equal or better priority" do
      @pq.push [10, Time.now, 1]

      t = Thread.new { Thread.current[:id] = @pq.shift(5)[-1] }
      sleep_until { t.status == 'sleep' }

      @pq.push [10, Time.now, 2]
      sleep_until { t.status == 'sleep' }

      @pq.push [5, Time.now, 3]
      sleep_until { t.status == false }

      t[:id].should == 3
    end

    it "when blocking for multiple threads should only return for one of sufficient priority" do
      # Randomize order in which threads lock.
      threads = [5, 10, 15, 20].shuffle.map do |priority|
        Thread.new do
          Thread.current[:priority] = priority
          Thread.current[:result] = @pq.shift(priority)
        end
      end

      sleep_until { threads.all? { |t| t.status == 'sleep' } }

      threads.sort_by! { |t| t[:priority] }

      value = [17, Time.now, 1]
      @pq.push value

      sleep_until { threads[3].status == false }
      threads[3][:result].should == value
      sleep_until { threads[0..2].all? { |t| t.status == 'sleep' } }
    end
  end

  describe "#stop" do
    it "should return nil to waiting workers" do
      threads = 4.times.map { Thread.new { Thread.current[:result] = @pq.shift } }

      sleep_until { threads.all? { |t| t.status == 'sleep' } }
      @pq.stop
      sleep_until { threads.all? { |t| t.status == false } }

      threads.map { |t| t[:result].should == nil }
      10.times { @pq.shift.should == nil }
    end
  end

  describe "#clear" do
    it "should remove and return all items" do
      @pq.push *@array
      @pq.clear.sort.should == @array
      @pq.to_a.should == []
    end
  end

  it "should still be pushable and clearable if it has an infinite maximum_size" do
    # Results queues only need these two operations, and shouldn't have a size limit.
    @pq = Que::PriorityQueue.new
    value = [100, Time.now, 45]
    @pq.push value
    @pq.to_a.should == [value]
    @pq.clear.should == [value]
    @pq.to_a.should == []
  end
end
