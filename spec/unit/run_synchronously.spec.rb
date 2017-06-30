# frozen_string_literal: true

require 'spec_helper'

describe Que, "run_synchronously=" do
  before { Que::Job.run_synchronously = true  }
  after  { Que::Job.run_synchronously = false }

  it "should cause jobs to be worked synchronously" do
    assert_instance_of ArgsJob, ArgsJob.enqueue(1, 2, 3)
    assert_equal [1, 2, 3], $passed_args
  end

  it "should ignore jobs that are scheduled for a future date" do
    assert_instance_of ArgsJob, ArgsJob.enqueue(1, 2, 3, run_at: Time.now + 3)
    assert_nil $passed_args
  end
end
