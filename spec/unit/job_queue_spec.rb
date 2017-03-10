# frozen_string_literal: true

require 'spec_helper'

describe Que::JobQueue do
  before do
    @jq = Que::JobQueue.new maximum_size: 8

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
        assert_nil @jq.push(job)
        ids << job[-1]
        assert_equal ids.sort, @jq.to_a.map{|j| j[-1]}
      end
    end

    it "should be able to add many items at once" do
      assert_nil @jq.push(*@array.shuffle)
      assert_equal @array, @jq.to_a
    end

    it "when the max is reached should pop the least important jobs and return their ids to be unlocked" do
      @jq.push(*@array)
      assert_equal [@array[7]], @jq.push(@array[0])
      assert_equal @array[5..6], @jq.push(*@array[1..2]).sort
      assert_equal 8, @jq.size

      # Make sure pushing multiple items that cross the threshold works properly.
      @jq.clear
      @jq.push(*@array)
      assert_equal @array[0], @jq.shift
      assert_equal [@array[7]], @jq.push(*@array[0..1])
      assert_equal 8, @jq.size

      # Pushing very low priority jobs shouldn't happen, since we use
      # #accept? to prevent unnecessary locking, but just in case:
      v = [100, Time.now, 45]
      assert_equal [v], @jq.push(v)
      refute_includes @jq.to_a.map(&:first), 100
      assert_equal 8, @jq.size
    end
  end

  describe "#accept?" do
    before do
      @jq.push *@array
    end

    it "should return true if there is sufficient room in the queue" do
      assert_equal @array[0], @jq.shift
      assert_equal 7, @jq.size
      assert_equal true, @jq.accept?(@array[-1])
    end

    it "should return true if there is insufficient room in the queue, but the pk can knock out a lower-priority job" do
      assert_equal true, @jq.accept?(@array[0])
    end

    it "should return false if there is insufficient room in the queue, and the job's priority is lower than any in the queue" do
      assert_equal false, @jq.accept?(@array[-1])
    end
  end

  describe "#shift" do
    it "should return the lowest item by sort order" do
      @jq.push *@array
      assert_equal @array[0],    @jq.shift
      assert_equal @array[1..7], @jq.to_a
      assert_equal @array[1],    @jq.shift
      assert_equal @array[2..7], @jq.to_a
    end

    it "should block for multiple threads when the queue is empty" do
      threads = 4.times.map { Thread.new { Thread.current[:id] = @jq.shift } }

      sleep_until { threads.all? { |t| t.status == 'sleep' } }
      @jq.push *@array
      sleep_until { threads.all? { |t| t.status == false } }

      assert_equal (1..4).to_a, threads.map{|t| t[:id][-1]}.sort
    end

    it "should accept a priority value and only accept jobs of equal or better priority" do
      @jq.push [10, Time.now, 1]

      t = Thread.new { Thread.current[:id] = @jq.shift(5)[-1] }
      sleep_until { t.status == 'sleep' }

      @jq.push [10, Time.now, 2]
      sleep_until { t.status == 'sleep' }

      @jq.push [5, Time.now, 3]
      sleep_until { t.status == false }

      assert_equal 3, t[:id]
    end

    it "when blocking for multiple threads should only return for one of sufficient priority" do
      # Randomize order in which threads lock.
      threads = [5, 10, 15, 20].shuffle.map do |priority|
        Thread.new do
          Thread.current[:priority] = priority
          Thread.current[:result] = @jq.shift(priority)
        end
      end

      sleep_until { threads.all? { |t| t.status == 'sleep' } }

      threads.sort_by! { |t| t[:priority] }

      value = [17, Time.now, 1]
      @jq.push value

      sleep_until { threads[3].status == false }
      assert_equal value, threads[3][:result]
      sleep_until { threads[0..2].all? { |t| t.status == 'sleep' } }
    end
  end

  describe "#stop" do
    it "should return nil to waiting workers" do
      threads = 4.times.map { Thread.new { Thread.current[:result] = @jq.shift } }

      sleep_until { threads.all? { |t| t.status == 'sleep' } }
      @jq.stop
      sleep_until { threads.all? { |t| t.status == false } }

      threads.map { |t| assert_nil t[:result] }
      10.times { assert_nil @jq.shift }
    end
  end

  describe "#clear" do
    it "should remove and return all items" do
      @jq.push *@array
      assert_equal @array, @jq.clear.sort
      assert_equal [], @jq.to_a
    end

    it "should return an empty array if there are no items to clear" do
      assert_equal [], @jq.clear
      @jq.push *@array
      assert_equal @array, @jq.clear.sort
      assert_equal [], @jq.clear
    end
  end

  it "should still be pushable and clearable if it has an infinite maximum_size" do
    # Results queues only need these two operations, and shouldn't have a size limit.
    @jq = Que::JobQueue.new
    value = [100, Time.now, 45]
    @jq.push value
    assert_equal [value], @jq.to_a
    assert_equal [value], @jq.clear
    assert_equal [],      @jq.to_a
  end
end
