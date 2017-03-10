# frozen_string_literal: true

require 'spec_helper'

describe Que, "mode=" do
  it "should log the mode change" do
    Que.mode = :sync
    event = logged_messages.find { |m| m['event'] == 'mode_change' }
    assert_equal 'sync', event['value']
    assert_equal :sync, Que.mode
  end

  it "repeatedly should not do anything" do
    Que.mode = :sync
    Que.mode = :sync
    Que.mode = :sync

    assert_equal 1, logged_messages.select{|m| m['event'] == 'mode_change'}.count
  end

  describe ":off" do
    before { Que.mode = :off }

    it "should insert jobs into the database" do
      Que::Job.enqueue
      assert_equal ['Que::Job'], DB[:que_jobs].select_map(:job_class)
    end
  end

  describe ":sync" do
    before { Que.mode = :sync }

    it "should work jobs synchronously" do
      assert_instance_of ArgsJob, ArgsJob.enqueue(1, 2, 3)
      assert_equal [1, 2, 3], $passed_args
      assert_equal :sync, Que.mode
    end

    it "should not work jobs synchronously if they are scheduled for a future date" do
      assert_instance_of ArgsJob, ArgsJob.enqueue(1, 2, 3, run_at: Time.now + 3)
      assert_nil $passed_args
      assert_equal :sync, Que.mode
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

    it "then Que.mode = :async a second time should not do anything" do
      Que.mode = :async
      Que.mode = :async
      assert_equal :async, Que.mode
    end

    it "then Que.mode = :off should gracefully shut down the locker" do
      Que.mode = :async
      sleep_until { DB[:que_lockers].count == 1 }
      BlockJob.enqueue
      $q1.pop
      $q2.push nil
      Que.mode = :off
      assert_empty DB[:que_jobs]
    end

    it "then Que.mode = :sync should gracefully shut down the locker" do
      Que.mode = :async
      sleep_until { DB[:que_lockers].count == 1 }
      BlockJob.enqueue
      $q1.pop
      $q2.push nil
      Que.mode = :sync
      assert_empty DB[:que_jobs]
    end
  end
end
