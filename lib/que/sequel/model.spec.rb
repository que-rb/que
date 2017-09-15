# frozen_string_literal: true

require 'spec_helper'

describe Que::Sequel::Model do
  it "should be able to load, modify and update jobs" do
    job_attrs = Que::Job.enqueue.que_attrs

    job = Que::Sequel::Model[job_attrs[:id]]

    assert_instance_of Que::Sequel::Model, job
    assert_equal job_attrs[:id], job.id

    assert_equal "default", job.queue
    job.update queue: "custom_queue"

    assert_equal "custom_queue", DB[:que_jobs].get(:queue)
  end
end
