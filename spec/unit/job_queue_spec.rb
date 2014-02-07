require 'spec_helper'

describe Que::JobQueue do
  before do
    @jq = Que::JobQueue.new(8)

    older = Time.now - 50
    newer = Time.now

    @array = [
      {:priority => 1, :run_at => older, :job_id => 1},
      {:priority => 1, :run_at => older, :job_id => 2},
      {:priority => 1, :run_at => newer, :job_id => 3},
      {:priority => 1, :run_at => newer, :job_id => 4},
      {:priority => 2, :run_at => older, :job_id => 5},
      {:priority => 2, :run_at => older, :job_id => 6},
      {:priority => 2, :run_at => newer, :job_id => 7},
      {:priority => 2, :run_at => newer, :job_id => 8}
    ]
  end

  describe "#push" do
    it "should add a pk and retain the sort order" do
      ids = []
      @array.shuffle.each do |job|
        @jq.push(job).should be nil
        ids << job[:job_id]
        @jq.to_a.map{|j| j[:job_id]}.should == ids.sort
      end
    end

    it "should be able to add many items at once" do
      @jq.push(@array.shuffle).should be nil
      @jq.to_a.should == @array
    end

    it "when the max is reached should pop the least important jobs and return their ids to be unlocked" do
      @jq.push(@array)
      @jq.push(@array[0]).should == [8]
      @jq.push(@array[1..2]).sort.should == [6, 7]
      @jq.size.should == 8

      # Make sure pushing multiple items that cross the threshold works properly.
      @jq.clear
      @jq.push(@array)
      @jq.shift
      @jq.push(@array[0..1]).should == [8]
      @jq.size.should == 8

      # Pushing very low priority jobs shouldn't happen, since we use
      # #accept? to prevent unnecessary locking, but just in case:
      @jq.push(:priority => 100, :run_at => Time.now, :job_id => 45).should == [45]
      @jq.to_a.map{|h| h[:job_id]}.should_not include 45
      @jq.size.should == 8
    end
  end

  describe "#accept?" do
    before do
      @jq.push @array
    end

    it "should return true if there is sufficient room in the queue" do
      @jq.shift[:job_id].should == 1
      @jq.size.should be 7
      @jq.accept?(@array[-1]).should be true
    end

    it "should return true if there is insufficient room in the queue, but the pk can knock out a lower-priority job" do
      @jq.accept?(@array[0]).should be true
    end

    it "should return false if there is insufficient room in the queue, and the job's priority is lower than any in the queue" do
      @jq.accept?(@array[-1]).should be false
    end
  end

  describe "#shift" do
    it "should return the lowest item by sort order" do
      @jq.push @array
      @jq.shift[:job_id].should == 1
      @jq.to_a.should == @array[1..7]
      @jq.shift[:job_id].should == 2
      @jq.to_a.should == @array[2..7]
    end

    it "should block for multiple threads when the queue is empty" do
      threads = 4.times.map { Thread.new { Thread.current[:id] = @jq.shift[:job_id] } }

      sleep_until { threads.all? { |t| t.status == 'sleep' } }
      @jq.push @array
      sleep_until { threads.all? { |t| t.status == false } }

      threads.map{|t| t[:id]}.sort.should == (1..4).to_a
    end

    it "should accept a priority value and only accept jobs of equal or better priority" do
      @jq.push :priority => 10,
               :run_at   => Time.now,
               :job_id   => 1

      t = Thread.new { Thread.current[:id] = @jq.shift(5)[:job_id] }
      sleep_until { t.status == 'sleep' }

      @jq.push :priority => 10,
               :run_at   => Time.now,
               :job_id   => 2

      sleep_until { t.status == 'sleep' }

      @jq.push :priority => 5,
               :run_at => Time.now,
               :job_id => 3

      sleep_until { t.status == false }
      t[:id].should == 3
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

      @jq.push :priority => 17,
               :run_at   => Time.now,
               :job_id   => 1

      sleep_until { threads[3].status == false }
      threads[3][:result][:job_id].should == 1
      sleep_until { threads[0..2].all? { |t| t.status == 'sleep' } }
    end
  end

  describe "#stop" do
    it "should return a :stop notification to waiting workers" do
      threads = 4.times.map { Thread.new { Thread.current[:result] = @jq.shift } }

      sleep_until { threads.all? { |t| t.status == 'sleep' } }
      @jq.stop
      sleep_until { threads.all? { |t| t.status == false } }

      threads.map { |t| t[:result].should == :stop }
      10.times { @jq.shift.should == :stop }
    end
  end

  describe "#clear" do
    it "should remove all pks and return their job_ids" do
      @jq.push @array
      @jq.clear.sort.should == (1..8).to_a
      @jq.to_a.should == []
    end
  end
end
