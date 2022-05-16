# frozen_string_literal: true

require 'spec_helper'

describe Que::Job, "run_synchronously=" do
  describe "on the base class" do
    before { Que::Job.run_synchronously = true }
    after  { Que::Job.remove_instance_variable(:@run_synchronously) }

    it "should cause jobs to be worked synchronously" do
      assert_instance_of ArgsJob, ArgsJob.enqueue(1, 2, 3)
      assert_equal [1, 2, 3], $passed_args
    end

    it "should ignore jobs that are scheduled for a future date" do
      assert_instance_of ArgsJob, ArgsJob.enqueue(1, 2, 3, job_options: { run_at: Time.now + 3 })
      assert_nil $passed_args
    end
  end

  describe "on a subclass" do
    before { ArgsJob.run_synchronously = true }
    after  { ArgsJob.remove_instance_variable(:@run_synchronously) }

    it "should cause jobs of that subclass to be worked synchronously" do
      assert_instance_of ArgsJob, ArgsJob.enqueue(1, 2, 3)
      assert_equal [1, 2, 3], $passed_args

      job = BlockJob.enqueue(1, 2, 3)
      assert_equal [job.que_attrs[:id]], jobs_dataset.select_map(:id)
    end

    it "should ignore jobs that are scheduled for a future date" do
      assert_instance_of ArgsJob, ArgsJob.enqueue(1, 2, 3, job_options: { run_at: Time.now + 3 })
      assert_nil $passed_args
    end
  end
end
