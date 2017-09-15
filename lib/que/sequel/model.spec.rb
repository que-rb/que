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

  describe "errored" do
    it "should return a dataset of jobs that have errored"
  end

  describe "expired" do
    it "should return a dataset of jobs that have expired"
  end

  describe "finished" do
    it "should return a dataset of jobs that have finished"
  end

  describe "scheduled" do
    it "should return a dataset of jobs that are scheduled for the future"
  end

  describe "ready" do
    it "should return a dataset of unerrored jobs that are ready to be run"
  end

  describe "by_job_class" do
    it "should return a dataset of jobs with that job class"

    it "should be compatible with ActiveModel job classes"
  end

  describe "by_queue" do
    it "should return a dataset of jobs in that queue"
  end

  describe "by_tag" do
    it "should return a dataset of jobs with the given tag"
  end

  describe "by_args" do
    it "should return a dataset of jobs whose args contain the given value"
  end
end
