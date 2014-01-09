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
      sleep_until { @worker.sleeping? }

      Que::Job.queue
      Que::Job.queue
      DB[:que_jobs].count.should be 2

      @worker.wake!.should be true
      sleep_until { @worker.sleeping? }
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
    begin
      ErrorJob.queue :priority => 1
      Que::Job.queue :priority => 5

      @worker = Que::Worker.new

      sleep_until { @worker.sleeping? }

      DB[:que_jobs].count.should be 1
      job = DB[:que_jobs].first
      job[:job_class].should == 'ErrorJob'
      job[:run_at].should be_within(3).of Time.now + 4
    ensure
      if @worker
        @worker.thread.kill
        @worker.thread.join
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
    ensure
      if @worker
        @worker.thread.kill
        @worker.thread.join
      end
    end
  end

  it "should receive and respect a notification to stop when it is currently asleep" do
    begin
      @worker = Que::Worker.new
      sleep_until { @worker.sleeping? }

      @worker.stop
      @worker.wait_until_stopped
    ensure
      if @worker
        @worker.thread.kill
        @worker.thread.join
      end
    end
  end

  it "should receive and respect a notification to stop immediately when it is working, and kill the job" do
    begin
      # Worker#stop! can leave the database connection in an unpredictable
      # state, which would impact the rest of the tests, so we need a special
      # connection for it.
      pg = NEW_PG_CONNECTION.call
      Que.connection = pg

      error_handled = false
      Que.error_handler = proc { |error| error_handled = true }

      BlockJob.queue

      @worker = Que::Worker.new
      $q1.pop
      @worker.stop!
      @worker.wait_until_stopped

      error_handled.should be false

      job = DB[:que_jobs].first
      job[:error_count].should be 0
      job[:last_error].should be nil
    ensure
      Que.error_handler = nil
      pg.close if pg
    end
  end

  it "should receive and respect a notification to stop immediately when it is currently asleep" do
    begin
      @worker = Que::Worker.new
      sleep_until { @worker.sleeping? }

      @worker.stop!
      @worker.wait_until_stopped
    ensure
      if @worker
        @worker.thread.kill
        @worker.thread.join
      end
    end
  end

  it "should be able to stop a job early when the job specifies that it's safe" do
    begin
      error_handled = false
      Que.error_handler = proc { |error| error_handled = true }

      $q1 = Queue.new

      class EarlyStopJob < Que::Job
        def run
          $q1.pop
          safe_to_stop
          $q1.pop
        end
      end

      EarlyStopJob.queue
      @worker = Que::Worker.new
      @worker.stop
      $q1.push nil
      @worker.wait_until_stopped

      error_handled.should be false

      job = DB[:que_jobs].first
      job[:error_count].should be 0
      job[:last_error].should be nil
    ensure
      Que.error_handler = nil
    end
  end
end
