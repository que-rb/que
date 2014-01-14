require 'spec_helper'

describe Que::Worker do
  it "should work jobs when started until there are none available" do
    begin
      Que::Job.queue
      Que::Job.queue
      DB[:que_jobs].count.should be 2

      @worker = Que::Worker.new
      sleep_until { @worker.sleeping? }
      DB[:que_jobs].count.should be 0

      $logger.messages.map{|m| JSON.load(m)['event']}.should == %w(job_worked job_worked job_unavailable)

      json = JSON.load($logger.messages[0])
      json['job']['job_class'].should == 'Que::Job'
    ensure
      if @worker
        @worker.stop
        @worker.wait_until_stopped
      end
    end
  end

  it "#wake! should return truthy if the worker was asleep and is woken up, at which point it should work until no jobs are available" do
    begin
      @worker = Que::Worker.new
      sleep_until { @worker.sleeping? }

      Que::Job.queue
      Que::Job.queue
      DB[:que_jobs].count.should be 2

      @worker.wake!.should be true
      sleep_until { @worker.sleeping? }
      DB[:que_jobs].count.should be 0
    ensure
      if @worker
        @worker.stop
        @worker.wait_until_stopped
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
      $q2.push nil
    ensure
      if @worker
        @worker.stop
        @worker.wait_until_stopped
      end
    end
  end

  it "should not be deterred by a job that raises an error" do
    begin
      ErrorJob.queue :priority => 1
      Que::Job.queue :priority => 5

      @worker = Que::Worker.new

      sleep_until { @worker.sleeping? }

      DB[:que_jobs].count.should be 1
      job = DB[:que_jobs].first
      job[:job_class].should == 'ErrorJob'
      job[:run_at].should be_within(3).of Time.now + 4

      log = JSON.load($logger.messages[0])
      log['event'].should == 'job_errored'
      log['error']['class'].should == 'RuntimeError'
      log['error']['message'].should == "ErrorJob!"
      log['job']['job_class'].should == 'ErrorJob'
    ensure
      if @worker
        @worker.stop
        @worker.wait_until_stopped
      end
    end
  end

  it "should receive and respect a notification to stop down when it is working, after its current job completes" do
    begin
      BlockJob.queue :priority => 1
      Que::Job.queue :priority => 5
      DB[:que_jobs].count.should be 2

      @worker = Que::Worker.new

      $q1.pop
      @worker.stop
      $q2.push nil

      @worker.wait_until_stopped

      DB[:que_jobs].count.should be 1
      job = DB[:que_jobs].first
      job[:job_class].should == 'Que::Job'
    end
  end

  it "should receive and respect a notification to stop when it is currently asleep" do
    begin
      @worker = Que::Worker.new
      sleep_until { @worker.sleeping? }

      @worker.stop
      @worker.wait_until_stopped
    end
  end
end
