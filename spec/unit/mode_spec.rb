require 'spec_helper'

describe Que, "mode=" do
  it "should log the mode change" do
    Que.mode = :sync
    event = logged_messages.find { |m| m['event'] == 'mode_change' }
    event['value'].should == 'sync'
    Que.mode.should == :sync
  end

  it "repeatedly should not do anything" do
    Que.mode = :sync
    Que.mode = :sync
    Que.mode = :sync

    logged_messages.select{|m| m['event'] == 'mode_change'}.count.should be 1
  end

  describe ":off" do
    before { Que.mode = :off }

    it "should insert jobs into the database" do
      Que::Job.enqueue
      DB[:que_jobs].select_map(:job_class).should == ['Que::Job']
    end
  end

  describe ":sync" do
    before { Que.mode = :sync }

    it "should work jobs synchronously" do
      ArgsJob.enqueue(1, 2, 3).should be_an_instance_of ArgsJob
      $passed_args.should == [1, 2, 3]
      Que.mode.should == :sync
    end

    it "should not work jobs synchronously if they are scheduled for a future date" do
      ArgsJob.enqueue(1, 2, 3, :run_at => Time.now + 3).should be_an_instance_of ArgsJob
      $passed_args.should == nil
      Que.mode.should == :sync
    end
  end

  describe ":async" do
    it "should start up a locker" do
      Que::Job.enqueue
      Que.mode = :async
      sleep_until { DB[:que_jobs].empty? }

      Que::Job.enqueue
      sleep_until { DB[:que_jobs].empty? }
      Que.mode = :off
    end

    it "should start up a locker that respects settings from environment variables" do
      pending

      # begin
      #   ENV['QUE_QUEUE'] = 'other_queue'

      #   Que::Job.enqueue :queue => 'other_queue'
      #   Que.mode = :async
      #   sleep_until { DB[:que_jobs].empty? }

      #   Que::Job.enqueue :queue => 'other_queue'
      #   sleep_until { DB[:que_jobs].empty? }
      #   Que.mode = :off
      # ensure
      #   ENV.delete('QUE_QUEUE')
      # end
    end

    it "then Que.mode = :async a second time should not do anything" do
      Que.mode = :async
      Que.mode = :async
      Que.mode.should == :async
    end

    it "then Que.mode = :off should gracefully shut down the locker" do
      Que.mode = :async
      BlockJob.enqueue
      $q1.pop
      $q2.push nil
      Que.mode = :off
    end

    it "then Que.mode = :sync should gracefully shut down the locker" do
      Que.mode = :async
      BlockJob.enqueue
      $q1.pop
      $q2.push nil
      Que.mode = :sync
    end
  end
end
