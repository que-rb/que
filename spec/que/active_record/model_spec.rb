# frozen_string_literal: true

require 'spec_helper'

if defined?(::ActiveRecord)
  describe 'Que::ActiveRecord::Model' do
    before do
      require "que/active_record/model"
    end

    def enqueue_job(*args, **kwargs)
      Que::Job.enqueue(*args, **kwargs).que_attrs[:id]
    end

    def assert_ids(*expected)
      actual = yield(Que::ActiveRecord::Model).pluck(:id).sort
      assert_equal expected, actual
    end

    it "should be able to load, modify and update jobs" do
      id = enqueue_job
      job = Que::ActiveRecord::Model.find(id)

      assert_instance_of Que::ActiveRecord::Model, job
      assert_equal id, job.id

      assert_equal "default", job.queue
      job.update queue: "custom_queue"

      assert_equal "custom_queue", DB[:que_jobs].where(id: id).get(:queue)
    end

    it "should work when using a subclass of the model" do
      id = enqueue_job
      klass = Class.new(Que::ActiveRecord::Model)
      job = klass.find(id)
      assert_equal id, job.id

      assert_equal "default", job.queue
      job.update queue: "custom_queue"

      assert_equal "custom_queue", DB[:que_jobs].where(id: id).get(:queue)

      # Make sure that scopes work.
      assert_equal 1, klass.not_finished.count
    end

    describe "errored" do
      it "should return a dataset of jobs that have errored" do
        a, b = 2.times.map { enqueue_job }
        assert_equal 1, jobs_dataset.where(id: a).update(error_count: 1)

        assert_ids(a) { |ds| ds.errored }
        assert_ids(b) { |ds| ds.not_errored }
      end
    end

    describe "expired" do
      it "should return a dataset of jobs that have expired" do
        a, b = 2.times.map { enqueue_job }
        assert_equal 1, jobs_dataset.where(id: a).update(expired_at: Time.now)

        assert_ids(a) { |ds| ds.expired }
        assert_ids(b) { |ds| ds.not_expired }
      end
    end

    describe "finished" do
      it "should return a dataset of jobs that have finished" do
        a, b = 2.times.map { enqueue_job }
        assert_equal 1, jobs_dataset.where(id: a).update(finished_at: Time.now)

        assert_ids(a) { |ds| ds.finished }
        assert_ids(b) { |ds| ds.not_finished }
      end
    end

    describe "scheduled" do
      it "should return a dataset of jobs that are scheduled for the future" do
        a, b = 2.times.map { enqueue_job }
        assert_equal 1, jobs_dataset.where(id: a).update(run_at: Time.now + 60)

        assert_ids(a) { |ds| ds.scheduled }
        assert_ids(b) { |ds| ds.not_scheduled }
      end
    end

    describe "ready" do
      it "should return a dataset of unerrored jobs that are ready to be run" do
        a, b, c, d, e = 5.times.map { enqueue_job }
        assert_equal 1, jobs_dataset.where(id: a).update(error_count: 1)
        assert_equal 1, jobs_dataset.where(id: b).update(expired_at: Time.now)
        assert_equal 1, jobs_dataset.where(id: c).update(finished_at: Time.now)
        assert_equal 1, jobs_dataset.where(id: d).update(run_at: Time.now + 60)

        assert_ids(e) { |ds| ds.ready }
        assert_ids(a, b, c, d) { |ds| ds.not_ready }
      end
    end

    describe "by_job_class" do
      it "should return a dataset of jobs with that job class" do
        a = enqueue_job(job_options: { job_class: "CustomJobClass" })
        b = enqueue_job(job_options: { job_class: "BlockJob" })
        c = enqueue_job

        assert_ids(a) { |ds| ds.by_job_class("CustomJobClass") }
        assert_ids(b) { |ds| ds.by_job_class("BlockJob") }
        assert_ids(b) { |ds| ds.by_job_class(BlockJob) }
        assert_ids(c) { |ds| ds.by_job_class(Que::Job) }
        assert_ids    { |ds| ds.by_job_class("NonexistentJobClass") }
      end

      it "should be compatible with ActiveModel job classes" do
        a = enqueue_job({job_class: "WrappedJobClass"}, job_options: { job_class: "ActiveJob::QueueAdapters::QueAdapter::JobWrapper" })
        b = enqueue_job({job_class: "OtherWrappedJobClass"}, job_options: { job_class: "ActiveJob::QueueAdapters::QueAdapter::JobWrapper" })
        enqueue_job

        assert_ids(a) { |ds| ds.by_job_class("WrappedJobClass") }
        assert_ids(b) { |ds| ds.by_job_class("OtherWrappedJobClass") }
        assert_ids    { |ds| ds.by_job_class("NonexistentJobClass") }
      end
    end

    describe "by_queue" do
      it "should return a dataset of jobs in that queue" do
        a = enqueue_job
        b = enqueue_job(job_options: { queue: "other_queue" })

        assert_ids(a) { |ds| ds.by_queue("default") }
        assert_ids(b) { |ds| ds.by_queue("other_queue") }
        assert_ids    { |ds| ds.by_queue("nonexistent_queue") }
      end
    end

    describe "by_tag" do
      it "should return a dataset of jobs with the given tag" do
        a = enqueue_job(job_options: { tags: ["tag_1"] })
        b = enqueue_job(job_options: { tags: ["tag_2"] })

        assert_ids(a) { |ds| ds.by_tag("tag_1") }
        assert_ids(b) { |ds| ds.by_tag("tag_2") }
        assert_ids    { |ds| ds.by_tag("nonexistent_tag") }
      end
    end

    describe "by_args" do
      it "should return a dataset of jobs whose args contain the given value" do
        a = enqueue_job "arg_string"
        b = enqueue_job arg: "arg_string"
        c = enqueue_job arg_hash: {arg: "arg_string"}
        enqueue_job

        assert_ids(a) { |ds| ds.by_args("arg_string") }
        assert_ids    { |ds| ds.by_args("nonexistent_arg_string") }
        assert_ids(b) { |ds| ds.by_args(arg: "arg_string") }
        assert_ids    { |ds| ds.by_args(arg: "nonexistent_arg_string") }
        assert_ids(c) { |ds| ds.by_args(arg_hash: {arg: "arg_string"}) }
        assert_ids    { |ds| ds.by_args(arg_hash: {arg: "nonexistent_arg_string"}) }
      end
    end
  end
end
