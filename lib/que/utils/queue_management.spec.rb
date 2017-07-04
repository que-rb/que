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
    it "should migrate the job queue to version #1" do
      Que.migrate! version: 0
      assert_equal 0, Que.db_version
      Que.create!
      assert_equal 1, Que.db_version
      Que.migrate!
    end
  end

  describe "drop!" do
    it "should drop the job queue entirely" do
      refute_equal 0, Que.db_version
      Que.drop!
      assert_equal 0, Que.db_version
      Que.migrate!
    end
  end
end
