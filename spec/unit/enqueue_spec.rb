# frozen_string_literal: true

require 'spec_helper'

describe Que::Job, '.enqueue' do
  def assert_enqueue(args, expected_priority: 100, expected_run_at: Time.now,
    expected_job_class: Que::Job, expected_args: [])

    assert_equal 0, DB[:que_jobs].count

    result =
      if args.respond_to?(:call)
        args.call
      else
        Que.enqueue(*args)
      end

    assert_equal 1, DB[:que_jobs].count

    assert_kind_of Que::Job, result
    assert_equal expected_priority, result.attrs[:priority]
    assert_equal expected_args, result.attrs[:args]

    job = DB[:que_jobs].first
    assert_equal expected_priority, job[:priority]
    assert_in_delta job[:run_at], expected_run_at, 3
    assert_equal expected_job_class.to_s, job[:job_class]
    assert_equal expected_args, JSON.parse(job[:args], symbolize_names: true)

    DB[:que_jobs].delete
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

  it "should be able to queue a job with queueing options in addition to argument options" do
    assert_enqueue [1, {string: "string", run_at: Time.now + 60, priority: 4}],
      expected_args: [1, {string: "string"}],
      expected_run_at: Time.now + 60,
      expected_priority: 4
  end

  it "should respect a job class defined as a string" do
    class MyJobClass < Que::Job
    end

    assert_enqueue ['argument', {other_arg: "other_arg", job_class: 'MyJobClass'}],
      expected_args: ['argument', {other_arg: "other_arg"}],
      expected_job_class: MyJobClass
  end

  it "should respect a default (but overridable) priority for the job class" do
    class DefaultPriorityJob < Que::Job
      @priority = 3
    end

    assert_enqueue \
      -> { DefaultPriorityJob.enqueue 1 },
      expected_args: [1],
      expected_priority: 3,
      expected_job_class: DefaultPriorityJob

    assert_enqueue \
      -> { DefaultPriorityJob.enqueue 1, priority: 4 },
      expected_args: [1],
      expected_priority: 4,
      expected_job_class: DefaultPriorityJob
  end

  it "should respect a default (but overridable) run_at for the job class" do
    class DefaultRunAtJob < Que::Job
      @run_at = -> { Time.now + 30 }
    end

    assert_enqueue \
      -> { DefaultRunAtJob.enqueue 1 },
      expected_args: [1],
      expected_run_at: Time.now + 30,
      expected_job_class: DefaultRunAtJob

    assert_enqueue \
      -> { DefaultRunAtJob.enqueue 1, run_at: Time.now + 60 },
      expected_args: [1],
      expected_run_at: Time.now + 60,
      expected_job_class: DefaultRunAtJob
  end
end
