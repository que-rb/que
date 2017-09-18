# frozen_string_literal: true

require 'spec_helper'

describe 'Que::Sequel::Model' do
  before do
    require "que/sequel/model"
  end

  def enqueue_job(*args)
    Que::Job.enqueue(*args).que_attrs[:id]
  end

  it "should be able to load, modify and update jobs" do
    id = enqueue_job
    job = Que::Sequel::Model[id]

    assert_instance_of Que::Sequel::Model, job
    assert_equal id, job.id

    assert_equal "default", job.queue
    job.update queue: "custom_queue"

    assert_equal "custom_queue", DB[:que_jobs].where(id: id).get(:queue)
  end

  describe "errored" do
    it "should return a dataset of jobs that have errored" do
      a, b = 2.times.map { enqueue_job }
      assert_equal 1, jobs_dataset.where(id: a).update(error_count: 1)

      assert_equal [a], Que::Sequel::Model.errored.select_map(:id)
      assert_equal [b], Que::Sequel::Model.not_errored.select_map(:id)
    end
  end

  describe "expired" do
    it "should return a dataset of jobs that have expired" do
      a, b = 2.times.map { enqueue_job }
      assert_equal 1, jobs_dataset.where(id: a).update(expired_at: Time.now)

      assert_equal [a], Que::Sequel::Model.expired.select_map(:id)
      assert_equal [b], Que::Sequel::Model.not_expired.select_map(:id)
    end
  end

  describe "finished" do
    it "should return a dataset of jobs that have finished" do
      a, b = 2.times.map { enqueue_job }
      assert_equal 1, jobs_dataset.where(id: a).update(finished_at: Time.now)

      assert_equal [a], Que::Sequel::Model.finished.select_map(:id)
      assert_equal [b], Que::Sequel::Model.not_finished.select_map(:id)
    end
  end

  describe "scheduled" do
    it "should return a dataset of jobs that are scheduled for the future" do
      a, b = 2.times.map { enqueue_job }
      assert_equal 1, jobs_dataset.where(id: a).update(run_at: Time.now + 60)

      assert_equal [a], Que::Sequel::Model.scheduled.select_map(:id)
      assert_equal [b], Que::Sequel::Model.not_scheduled.select_map(:id)
    end
  end

  describe "ready" do
    it "should return a dataset of unerrored jobs that are ready to be run" do
      a, b, c, d, e = 5.times.map { enqueue_job }
      assert_equal 1, jobs_dataset.where(id: a).update(error_count: 1)
      assert_equal 1, jobs_dataset.where(id: b).update(expired_at: Time.now)
      assert_equal 1, jobs_dataset.where(id: c).update(finished_at: Time.now)
      assert_equal 1, jobs_dataset.where(id: d).update(run_at: Time.now + 60)

      assert_equal [e], Que::Sequel::Model.ready.select_map(:id)
      assert_equal [a, b, c, d], Que::Sequel::Model.not_ready.select_order_map(:id)
    end
  end

  describe "by_job_class" do
    it "should return a dataset of jobs with that job class" do
      a = enqueue_job(job_class: "CustomJobClass")
      b = enqueue_job(job_class: "BlockJob")
      c = enqueue_job

      assert_equal [a], Que::Sequel::Model.by_job_class("CustomJobClass").select_map(:id)
      assert_equal [b], Que::Sequel::Model.by_job_class("BlockJob").select_map(:id)
      assert_equal [b], Que::Sequel::Model.by_job_class(BlockJob).select_map(:id)
      assert_equal [c], Que::Sequel::Model.by_job_class(Que::Job).select_map(:id)

      assert_equal [],  Que::Sequel::Model.by_job_class("NonexistentJobClass").select_map(:id)
    end

    it "should be compatible with ActiveModel job classes" do
      a = enqueue_job({job_class: "WrappedJobClass"}, {job_class: "ActiveJob::QueueAdapters::QueAdapter::JobWrapper"})
      b = enqueue_job({job_class: "OtherWrappedJobClass"}, {job_class: "ActiveJob::QueueAdapters::QueAdapter::JobWrapper"})
      c = enqueue_job

      assert_equal [a], Que::Sequel::Model.by_job_class("WrappedJobClass").select_map(:id)
      assert_equal [b], Que::Sequel::Model.by_job_class("OtherWrappedJobClass").select_map(:id)
      assert_equal [],  Que::Sequel::Model.by_job_class("NonexistentJobClass").select_map(:id)
    end
  end

  describe "by_queue" do
    it "should return a dataset of jobs in that queue" do
      a = enqueue_job
      b = enqueue_job(queue: "other_queue")

      assert_equal [a], Que::Sequel::Model.by_queue("default").select_map(:id)
      assert_equal [b], Que::Sequel::Model.by_queue("other_queue").select_map(:id)
      assert_equal [],  Que::Sequel::Model.by_queue("nonexistent_queue").select_map(:id)
    end
  end

  describe "by_tag" do
    it "should return a dataset of jobs with the given tag" do
      a = enqueue_job(tags: ["tag_1"])
      b = enqueue_job(tags: ["tag_2"])

      assert_equal [a], Que::Sequel::Model.by_tag("tag_1").select_map(:id)
      assert_equal [b], Que::Sequel::Model.by_tag("tag_2").select_map(:id)
      assert_equal [],  Que::Sequel::Model.by_tag("nonexistent_tag").select_map(:id)
    end
  end

  describe "by_args" do
    it "should return a dataset of jobs whose args contain the given value" do
      a = enqueue_job "arg_string"
      b = enqueue_job arg: "arg_string"
      c = enqueue_job arg_hash: {arg: "arg_string"}
      d = enqueue_job

      assert_equal [a], Que::Sequel::Model.by_args("arg_string").select_map(:id)
      assert_equal [],  Que::Sequel::Model.by_args("nonexistent_arg_string").select_map(:id)
      assert_equal [b], Que::Sequel::Model.by_args(arg: "arg_string").select_map(:id)
      assert_equal [],  Que::Sequel::Model.by_args(arg: "nonexistent_arg_string").select_map(:id)
      assert_equal [c], Que::Sequel::Model.by_args(arg_hash: {arg: "arg_string"}).select_map(:id)
      assert_equal [],  Que::Sequel::Model.by_args(arg_hash: {arg: "nonexistent_arg_string"}).select_map(:id)
    end
  end
end
