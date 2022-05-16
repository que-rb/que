# frozen_string_literal: true

require 'spec_helper'

describe Que::Utils::QueueManagement do
  describe "clear!" do
    it "should clear all jobs from the queue" do
      jobs_dataset.insert(job_class: "Que::Job", job_schema_version: Que.job_schema_version)
      assert_equal 1, jobs_dataset.count
      Que.clear!
      assert_equal 0, jobs_dataset.count
    end
  end

  describe "create!" do
    it "should migrate the job queue to version #1" do
      Que.migrate! version: 0
      assert_equal 0, Que.db_version
      Que.create!
      assert_equal 1, Que.db_version
      Que.migrate!(version: Que::Migrations::CURRENT_VERSION)
    end
  end

  describe "drop!" do
    it "should drop the job queue entirely" do
      refute_equal 0, Que.db_version
      Que.drop!
      assert_equal 0, Que.db_version
      Que.migrate!(version: Que::Migrations::CURRENT_VERSION)
    end
  end
end
