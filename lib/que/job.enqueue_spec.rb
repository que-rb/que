# frozen_string_literal: true

require 'spec_helper'

describe Que::Job, '.enqueue' do
  def assert_enqueue(
    args,
    expected_queue: 'default',
    expected_priority: 100,
    expected_run_at: Time.now,
    expected_job_class: Que::Job,
    expected_result_class: nil,
    expected_args: [],
    expected_tags: nil,
    expected_que_version: que_major_version
  )

    assert_equal 0, jobs_dataset.count

    result =
      if args.respond_to?(:call)
        args.call
      else
        Que.enqueue(*args)
      end

    assert_equal 1, jobs_dataset.count

    assert_kind_of Que::Job, result
    assert_instance_of (expected_result_class || expected_job_class), result

    assert_equal expected_priority, result.que_attrs[:priority]
    assert_equal expected_args, result.que_attrs[:args]

    if expected_tags.nil?
      assert_equal({}, result.que_attrs[:data])
    else
      assert_equal expected_tags, result.que_attrs[:data][:tags]
    end

    job = jobs_dataset.first
    assert_equal expected_queue, job[:queue]
    assert_equal expected_priority, job[:priority]
    assert_in_delta job[:run_at], expected_run_at, QueSpec::TIME_SKEW
    assert_equal expected_job_class.to_s, job[:job_class]
    assert_equal expected_args, job[:args]
    assert_equal expected_que_version, job[:que_version]

    jobs_dataset.delete
  end

  it "should be able to queue a job" do
    assert_enqueue []
  end

  it "should be able to queue a job with arguments" do
    assert_enqueue [1, 'two'],
      expected_args: [1, 'two']
  end

  it "should be able to queue a job with complex arguments" do
    assert_enqueue [
      1,
      'two',
      {
        string: "string",
        integer: 5,
        array: [1, "two", {three: 3}],
        hash: {one: 1, two: 'two', three: [3]},
      },
    ],
    expected_args: [
      1,
      'two',
      {
        string: "string",
        integer: 5,
        array: [1, "two", {three: 3}],
        hash: {one: 1, two: 'two', three: [3]},
      },
    ]
  end

  it "should be able to handle a namespaced job class" do
    assert_enqueue \
      -> { NamespacedJobNamespace::NamespacedJob.enqueue 1 },
      expected_args: [1],
      expected_job_class: NamespacedJobNamespace::NamespacedJob
  end

  it "should error appropriately on an anonymous job subclass" do
    klass = Class.new(Que::Job)

    error = assert_raises(Que::Error) { klass.enqueue 1 }

    assert_equal \
      "Can't enqueue an anonymous subclass of Que::Job",
      error.message
  end

  it "should be able to queue a job with a specific queue name" do
    assert_enqueue [1, {queue: 'special_queue_name'}],
      expected_args: [1],
      expected_queue: 'special_queue_name'
  end

  it "should be able to queue a job with a specific time to run" do
    assert_enqueue [1, {run_at: Time.now + 60}],
      expected_args: [1],
      expected_run_at: Time.now + 60
  end

  it "should be able to queue a job with a specific priority" do
    assert_enqueue [1, {priority: 4}],
      expected_args: [1],
      expected_priority: 4
  end

  it "should be able to queue a job with options in addition to args" do
    assert_enqueue \
      [1, {string: "string", run_at: Time.now + 60, priority: 4}],
      expected_args: [1, {string: "string"}],
      expected_run_at: Time.now + 60,
      expected_priority: 4
  end

  it "should be able to use an explicit `job_options` keyword to avoid conflicts with job keyword args" do
    assert_enqueue \
      [1, {string: "string", priority: 10, job_options: { priority: 15 }}],
      expected_args: [1, {string: "string", priority: 10}],
      expected_priority: 15
  end

  it "should fall back to using job options specified at the top level if not specified in job_options" do
    assert_enqueue \
      [1, {string: "string", run_at: Time.now + 60, priority: 10, job_options: { priority: 15 }}],
      expected_args: [1, {string: "string", priority: 10}],
      expected_run_at: Time.now + 60,
      expected_priority: 15
  end

  describe "when enqueuing a job with tags" do
    it "should be able to specify tags on a case-by-case basis" do
      assert_enqueue \
        [1, {string: "string", tags: ["tag_1", "tag_2"]}],
        expected_args: [1, {string: "string"}],
        expected_tags: ["tag_1", "tag_2"]
    end

    it "should be able to use multiple hashes to avoid conflicts with keywords" do
      assert_enqueue \
        [1, {string: "string", tags: ["tag_1", "tag_2"]}, {}],
        expected_args: [1, {string: "string", tags: ["tag_1", "tag_2"]}],
        expected_tags: nil
    end

    it "should be able to use an explicit `job_options` keyword to avoid conflicts with job keyword args" do
      assert_enqueue \
        [1, {string: "string", tags: ["tag_1", "tag_2"], job_options: { tags: ["tag_3", "tag_4"] }}],
        expected_args: [1, {string: "string", tags: ["tag_1", "tag_2"]}],
        expected_tags: ["tag_3", "tag_4"]
    end

    it "should raise an error if passing too many tags" do
      error =
        assert_raises(Que::Error) do
          Que::Job.enqueue 1, string: "string", tags: %w[a b c d e f]
        end

      assert_equal \
        "Can't enqueue a job with more than 5 tags! (passed 6)",
        error.message
    end

    it "should raise an error if any of the tags are too long" do
      error =
        assert_raises(Que::Error) do
          Que::Job.enqueue 1, string: "string", tags: ["a" * 101]
        end

      assert_equal \
        "Can't enqueue a job with a tag longer than 100 characters! (\"#{"a" * 101}\")",
        error.message
    end
  end

  it "should respect a job class defined as a string" do
    class MyJobClass < Que::Job; end

    assert_enqueue \
      ['argument', {other_arg: "other_arg", job_class: 'MyJobClass'}],
      expected_args: ['argument', {other_arg: "other_arg"}],
      expected_job_class: MyJobClass,
      expected_result_class: Que::Job
  end

  describe "when there's a hierarchy of job classes" do
    class PriorityDefaultJob < Que::Job
      self.priority = 3
    end

    class PrioritySubclassJob < PriorityDefaultJob
    end

    class RunAtDefaultJob < Que::Job
      self.run_at = -> { Time.now + 30 }
    end

    class RunAtSubclassJob < RunAtDefaultJob
    end

    class QueueDefaultJob < Que::Job
      self.queue = :queue_1
    end

    class QueueSubclassJob < QueueDefaultJob
    end

    describe "priority" do
      it "should respect a default priority in a job class" do
        assert_enqueue \
          -> { PriorityDefaultJob.enqueue 1 },
          expected_args: [1],
          expected_priority: 3,
          expected_job_class: PriorityDefaultJob

        assert_enqueue \
          -> { PriorityDefaultJob.enqueue 1, priority: 4 },
          expected_args: [1],
          expected_priority: 4,
          expected_job_class: PriorityDefaultJob
      end

      it "should respect an inherited priority in a job class" do
        assert_enqueue \
          -> { PrioritySubclassJob.enqueue 1 },
          expected_args: [1],
          expected_priority: 3,
          expected_job_class: PrioritySubclassJob

        assert_enqueue \
          -> { PrioritySubclassJob.enqueue 1, priority: 4 },
          expected_args: [1],
          expected_priority: 4,
          expected_job_class: PrioritySubclassJob
      end

      it "should respect an overridden priority in a job class" do
        begin
          PrioritySubclassJob.priority = 60

          assert_enqueue \
            -> { PrioritySubclassJob.enqueue 1 },
            expected_args: [1],
            expected_priority: 60,
            expected_job_class: PrioritySubclassJob

          assert_enqueue \
            -> { PrioritySubclassJob.enqueue 1, priority: 4 },
            expected_args: [1],
            expected_priority: 4,
            expected_job_class: PrioritySubclassJob
        ensure
          PrioritySubclassJob.remove_instance_variable(:@priority)
        end
      end
    end

    describe "run_at" do
      it "should respect a default run_at in a job class" do
        assert_enqueue \
          -> { RunAtDefaultJob.enqueue 1 },
          expected_args: [1],
          expected_run_at: Time.now + 30,
          expected_job_class: RunAtDefaultJob

        assert_enqueue \
          -> { RunAtDefaultJob.enqueue 1, run_at: Time.now + 60 },
          expected_args: [1],
          expected_run_at: Time.now + 60,
          expected_job_class: RunAtDefaultJob
      end

      it "should respect an inherited run_at in a job class" do
        assert_enqueue \
          -> { RunAtSubclassJob.enqueue 1 },
          expected_args: [1],
          expected_run_at: Time.now + 30,
          expected_job_class: RunAtSubclassJob

        assert_enqueue \
          -> { RunAtSubclassJob.enqueue 1, run_at: Time.now + 60 },
          expected_args: [1],
          expected_run_at: Time.now + 60,
          expected_job_class: RunAtSubclassJob
      end

      it "should respect an overridden run_at in a job class" do
        begin
          RunAtSubclassJob.run_at = -> {Time.now + 90}

          assert_enqueue \
            -> { RunAtSubclassJob.enqueue 1 },
            expected_args: [1],
            expected_run_at: Time.now + 90,
            expected_job_class: RunAtSubclassJob

          assert_enqueue \
            -> { RunAtSubclassJob.enqueue 1, run_at: Time.now + 60 },
            expected_args: [1],
            expected_run_at: Time.now + 60,
            expected_job_class: RunAtSubclassJob
        ensure
          RunAtSubclassJob.remove_instance_variable(:@run_at)
        end
      end
    end

    describe "queue" do
      it "should respect a default queue in a job class" do
        assert_enqueue \
          -> { QueueDefaultJob.enqueue 1 },
          expected_args: [1],
          expected_queue: 'queue_1',
          expected_job_class: QueueDefaultJob

        assert_enqueue \
          -> { QueueDefaultJob.enqueue 1, queue: 'queue_3' },
          expected_args: [1],
          expected_queue: 'queue_3',
          expected_job_class: QueueDefaultJob
      end

      it "should respect an inherited queue in a job class" do
        assert_enqueue \
          -> { QueueSubclassJob.enqueue 1 },
          expected_args: [1],
          expected_queue: 'queue_1',
          expected_job_class: QueueSubclassJob

        assert_enqueue \
          -> { QueueSubclassJob.enqueue 1, queue: 'queue_3' },
          expected_args: [1],
          expected_queue: 'queue_3',
          expected_job_class: QueueSubclassJob
      end

      it "should respect an overridden queue in a job class" do
        begin
          QueueSubclassJob.queue = :queue_2

          assert_enqueue \
            -> { QueueSubclassJob.enqueue 1 },
            expected_args: [1],
            expected_queue: 'queue_2',
            expected_job_class: QueueSubclassJob

          assert_enqueue \
            -> { QueueSubclassJob.enqueue 1, queue: 'queue_3' },
            expected_args: [1],
            expected_queue: 'queue_3',
            expected_job_class: QueueSubclassJob
        ensure
          QueueSubclassJob.remove_instance_variable(:@queue)
        end
      end
    end
  end
end
