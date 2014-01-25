require 'spec_helper'

describe Que::JobQueue do
  before do
    @jq = Que::JobQueue.new

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
    it "should add an item and retain the sort order" do
      ids = []
      @array.shuffle.each do |job|
        @jq.push(job)
        ids << job[:job_id]
        @jq.to_a.map{|j| j[:job_id]}.should == ids.sort
      end
    end

    it "should be able to add many items at once" do
      @jq.push(@array.shuffle)
      @jq.to_a.should == @array
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
end
