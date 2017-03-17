# frozen_string_literal: true

require 'spec_helper'

describe Que::JobQueue do
  before do
    @job_queue = Que::JobQueue.new(maximum_size: 8)

    @old = Time.now - 50
    @new = Time.now

    @job_array = [
      [1, @old, 1],
      [1, @old, 2],
      [1, @new, 3],
      [1, @new, 4],
      [2, @old, 5],
      [2, @old, 6],
      [2, @new, 7],
      [2, @new, 8],
    ]
  end

  describe "#push" do
    it "should add an item and retain the sort order" do
      ids = []

      @job_array.shuffle.each do |job|
        assert_nil @job_queue.push(job)
        ids << job[-1]
        assert_equal ids.sort, @job_queue.to_a.map{|j| j[-1]}
      end

      assert_equal @job_array, @job_queue.to_a
    end

    it "should be able to add many items at once" do
      assert_nil @job_queue.push(*@job_array.shuffle)
      assert_equal @job_array, @job_queue.to_a
    end

    describe "when the maximum size has been reached" do
      before do
        @job_queue.push(*@job_array)
      end

      it "should pop the least important jobs and return their pks" do
        assert_equal @job_array[7..7], @job_queue.push(@job_array[0])
        assert_equal @job_array[5..6], @job_queue.push(*@job_array[1..2]).sort
        assert_equal 8, @job_queue.size
      end

      it "should work when passing multiple pks that would pass the maximum" do
        assert_equal @job_array.first, @job_queue.shift
        assert_equal @job_array[7..7], @job_queue.push(*@job_array[0..1])
        assert_equal 8, @job_queue.size
      end

      # Pushing very low priority jobs shouldn't happen, since we use
      # #accept? to prevent unnecessary locking, but just in case:
      it "should work when the jobs wouldn't make the cut" do
        v = [100, Time.now, 45]
        assert_equal [v], @job_queue.push(v)
        refute_includes @job_queue.to_a, v
        assert_equal 8, @job_queue.size
      end
    end
  end

  describe "#accept?" do
    before do
      @job_queue.push *@job_array
    end

    it "should return true if there is sufficient room in the queue" do
      assert_equal @job_array.first, @job_queue.shift
      assert_equal 7, @job_queue.size
      assert_equal true, @job_queue.accept?(@job_array.last)
    end

    it "should return true if there is insufficient room in the queue, but the pk can knock out a lower-priority job" do
      assert_equal true, @job_queue.accept?(@job_array.first)
    end

    it "should return false if there is insufficient room in the queue, and the job's priority is lower than any in the queue" do
      assert_equal false, @job_queue.accept?(@job_array.last)
    end
  end

  describe "#shift" do
    it "should return the lowest item by sort order" do
      @job_queue.push *@job_array
      assert_equal @job_array[0],    @job_queue.shift
      assert_equal @job_array[1..7], @job_queue.to_a
      assert_equal @job_array[1],    @job_queue.shift
      assert_equal @job_array[2..7], @job_queue.to_a
    end

    it "should block for multiple threads when the queue is empty" do
      threads =
        4.times.map do
          Thread.new do
            Thread.current[:job] = @job_queue.shift
          end
        end

      sleep_until { threads.all? { |t| t.status == 'sleep' } }
      @job_queue.push *@job_array
      sleep_until { threads.all? { |t| t.status == false } }

      assert_equal @job_array[0..3], threads.map{|t| t[:job]}.sort
      assert_equal @job_array[4..7], @job_queue.to_a
    end

    it "should accept a priority value and only accept jobs of equal or better priority" do
      a = [10, Time.now, 1]
      b = [10, Time.now, 2]
      c = [ 5, Time.now, 3]

      @job_queue.push(a)
      t = Thread.new { Thread.current[:job] = @job_queue.shift(5) }
      sleep_until { t.status == 'sleep' }

      @job_queue.push(b)
      sleep_until { t.status == 'sleep' }

      @job_queue.push(c)
      sleep_until { t.status == false }

      assert_equal c, t[:job]
    end

    it "when blocking for multiple threads should only return for one of sufficient priority" do
      # Randomize order in which threads lock.
      threads = [5, 10, 15, 20].shuffle.map do |priority|
        Thread.new do
          Thread.current[:priority] = priority
          Thread.current[:job] = @job_queue.shift(priority)
        end
      end

      sleep_until { threads.all? { |t| t.status == 'sleep' } }

      threads.sort_by! { |t| t[:priority] }

      value = [17, Time.now, 1]
      @job_queue.push value

      sleep_until { threads[3].status == false }
      assert_equal value, threads[3][:job]
      sleep_until { threads[0..2].all? { |t| t.status == 'sleep' } }
    end
  end

  describe "#stop" do
    it "should return nil to waiting workers" do
      threads =
        4.times.map do
          Thread.new do
            Thread.current[:job] = @job_queue.shift
          end
        end

      sleep_until { threads.all? { |t| t.status == 'sleep' } }
      @job_queue.stop
      sleep_until { threads.all? { |t| t.status == false } }

      threads.map { |t| assert_nil t[:job] }
      10.times { assert_nil @job_queue.shift }
    end
  end

  describe "#clear" do
    it "should remove and return all items" do
      @job_queue.push *@job_array
      assert_equal @job_array, @job_queue.clear.sort
      assert_equal [], @job_queue.to_a
    end

    it "should return an empty array if there are no items to clear" do
      assert_equal [], @job_queue.clear
      @job_queue.push *@job_array
      assert_equal @job_array, @job_queue.clear.sort
      assert_equal [], @job_queue.clear
    end
  end

  it "should still be pushable and clearable if it has an infinite maximum_size" do
    # Result queues only need these two operations, and shouldn't have a size limit.
    @job_queue = Que::JobQueue.new
    value = [100, Time.now, 45]
    @job_queue.push value
    assert_equal [value], @job_queue.to_a
    assert_equal [value], @job_queue.clear
    assert_equal [],      @job_queue.to_a
  end
end
