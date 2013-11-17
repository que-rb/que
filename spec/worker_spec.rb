require 'spec_helper'

describe Que::Worker do
  # Handy job that blocks during execution until we let it go forward.
  class BlockJob < Que::Job
    def run
      $q1.push nil
      $q2.pop
    end
  end

  before do
    $q1, $q2 = Queue.new, Queue.new
  end

  it "should work jobs when started until there are none available" do
    begin
      Que::Job.queue
      Que::Job.queue
      DB[:que_jobs].count.should be 2

      @worker = Que::Worker.new
      sleep_until { @worker.asleep? }
      DB[:que_jobs].count.should be 0
    ensure
      if @worker
        @worker.thread.kill
        @worker.thread.join
      end
    end
  end

  it "#wake! should return truthy if the worker was asleep and is woken up, at which point it should work until no jobs are available" do
    begin
      @worker = Que::Worker.new
      sleep_until { @worker.asleep? }

      Que::Job.queue
      Que::Job.queue
      DB[:que_jobs].count.should be 2

      @worker.wake!.should be true
      sleep_until { @worker.asleep? }
      DB[:que_jobs].count.should be 0
    ensure
      if @worker
        @worker.thread.kill
        @worker.thread.join
      end
    end
  end

  it "#wake! should return falsy if the worker was already working" do
    begin
      BlockJob.queue
      @worker = Que::Worker.new

      $q1.pop
      DB[:que_jobs].count.should be 1
      @worker.wake!.should be nil
    ensure
      if @worker
        @worker.thread.kill
        @worker.thread.join
      end
    end
  end

  it "should not be deterred by a job that raises an error" do
    class WorkerErrorJob < Que::Job
      def run
        raise "WorkerErrorJob!"
      end
    end

    begin
      WorkerErrorJob.queue :priority => 1
      Que::Job.queue       :priority => 5

      @worker = Que::Worker.new

      sleep_until { @worker.asleep? }

      DB[:que_jobs].count.should be 1
      job = DB[:que_jobs].first
      job[:type].should == 'WorkerErrorJob'
      job[:run_at].should be_within(3).of Time.now + 4
    ensure
      if @worker
        @worker.thread.kill
        @worker.thread.join
      end
    end
  end

  it "should receive and respect a notification to shut down when it is working, after its current job completes" do
    begin
      BlockJob.queue :priority => 1
      Que::Job.queue :priority => 5
      DB[:que_jobs].count.should be 2

      @worker = Que::Worker.new

      $q1.pop
      @worker.stop!
      $q2.push nil

      @worker.wait_until_stopped

      DB[:que_jobs].count.should be 1
      job = DB[:que_jobs].first
      job[:type].should == 'Que::Job'
    ensure
      if @worker
        @worker.thread.kill
        @worker.thread.join
      end
    end
  end

  it "should receive and respect a notification to shut down when it is asleep" do
    begin
      @worker = Que::Worker.new
      sleep_until { @worker.asleep? }

      @worker.stop!
      @worker.wait_until_stopped
    ensure
      if @worker
        @worker.thread.kill
        @worker.thread.join
      end
    end
  end
end
