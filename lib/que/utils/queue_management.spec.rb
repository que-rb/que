# frozen_string_literal: true

require 'spec_helper'

describe Que::Utils::QueueManagement do
  describe "clear!" do
    it "should clear all jobs from the queue" do
      jobs.insert job_class: "Que::Job"
      assert_equal 1, jobs.count
      Que.clear!
      assert_equal 0, jobs.count
    end
  end

  describe "create!" do
    it "should migrate the job queue to version #1"
  end

  describe "drop!" do
    it "should drop the job queue entirely"
  end
end
