# frozen_string_literal: true

require 'spec_helper'

describe Que::Job, '.enqueue' do
  it "should be able to queue a job" do
    assert_equal 0, DB[:que_jobs].count
    result = Que::Job.enqueue
    assert_equal 1, DB[:que_jobs].count

    assert_instance_of Que::Job, result
    assert_equal 100, result.attrs[:priority]
    assert_equal [], result.attrs[:args]

    job = DB[:que_jobs].first
    assert_equal 100, job[:priority]
    assert_in_delta job[:run_at], Time.now, 3
    assert_equal 'Que::Job', job[:job_class]
    assert_equal [], JSON.load(job[:args])
  end

  it "should be able to queue a job with arguments" do
    assert_equal 0, DB[:que_jobs].count
    Que::Job.enqueue 1, 'two'
    assert_equal 1, DB[:que_jobs].count

    job = DB[:que_jobs].first
    assert_equal 100, job[:priority]
    assert_in_delta job[:run_at], Time.now, 3
    assert_equal 'Que::Job', job[:job_class]
    assert_equal [1, 'two'], JSON.load(job[:args])
  end

  it "should be able to queue a job with complex arguments" do
    assert_equal 0, DB[:que_jobs].count
    Que::Job.enqueue 1, 'two', string: "string",
                               integer: 5,
                               array: [1, "two", {three: 3}],
                               hash: {one: 1, two: 'two', three: [3]}

    assert_equal 1, DB[:que_jobs].count

    job = DB[:que_jobs].first
    assert_equal 100, job[:priority]
    assert_in_delta job[:run_at], Time.now, 3
    assert_equal 'Que::Job', job[:job_class]
    assert_equal [
      1,
      'two',
      {
        'string' => 'string',
        'integer' => 5,
        'array' => [1, "two", {"three" => 3}],
        'hash' => {'one' => 1, 'two' => 'two', 'three' => [3]}
      }
    ], JSON.load(job[:args])
  end

  it "should be able to queue a job with a specific time to run" do
    assert_equal 0, DB[:que_jobs].count
    Que::Job.enqueue 1, run_at: Time.now + 60
    assert_equal 1, DB[:que_jobs].count

    job = DB[:que_jobs].first
    assert_equal 100, job[:priority]
    assert_in_delta job[:run_at], Time.now + 60, 3
    assert_equal 'Que::Job', job[:job_class]
    assert_equal [1], JSON.load(job[:args])
  end

  it "should be able to queue a job with a specific priority" do
    assert_equal 0, DB[:que_jobs].count
    Que::Job.enqueue 1, priority: 4
    assert_equal 1, DB[:que_jobs].count

    job = DB[:que_jobs].first
    assert_equal 4, job[:priority]
    assert_in_delta job[:run_at], Time.now, 3
    assert_equal 'Que::Job', job[:job_class]
    assert_equal [1], JSON.load(job[:args])
  end

  it "should be able to queue a job with queueing options in addition to argument options" do
    assert_equal 0, DB[:que_jobs].count
    Que::Job.enqueue 1, string: "string", run_at: Time.now + 60, priority: 4
    assert_equal 1, DB[:que_jobs].count

    job = DB[:que_jobs].first
    assert_equal 4, job[:priority]
    assert_in_delta job[:run_at], Time.now + 60, 3
    assert_equal 'Que::Job', job[:job_class]
    assert_equal [1, {'string' => 'string'}], JSON.load(job[:args])
  end

  it "should respect a job class defined as a string" do
    Que.enqueue 'argument', other_arg: 'other_arg', job_class: 'MyJobClass'
    Que::Job.enqueue 'argument', other_arg: 'other_arg', job_class: 'MyJobClass'

    assert_equal 2, DB[:que_jobs].count
    DB[:que_jobs].all.each do |job|
      assert_equal 'MyJobClass', job[:job_class]
      assert_equal ['argument', {'other_arg' => 'other_arg'}], JSON.load(job[:args])
    end
  end

  it "should respect a default (but overridable) priority for the job class" do
    class DefaultPriorityJob < Que::Job
      @priority = 3
    end

    assert_equal 0, DB[:que_jobs].count
    DefaultPriorityJob.enqueue 1
    DefaultPriorityJob.enqueue 1, priority: 4
    assert_equal 2, DB[:que_jobs].count

    first, second = DB[:que_jobs].order(:job_id).all

    assert_equal 3, first[:priority]
    assert_in_delta first[:run_at], Time.now, 3
    assert_equal 'DefaultPriorityJob', first[:job_class]

    assert_equal [1], JSON.load(first[:args])

    assert_equal 4, second[:priority]
    assert_in_delta second[:run_at], Time.now, 3
    assert_equal 'DefaultPriorityJob', second[:job_class]

    assert_equal [1], JSON.load(second[:args])
  end

  it "should respect a default (but overridable) run_at for the job class" do
    class DefaultRunAtJob < Que::Job
      @run_at = -> { Time.now + 60 }
    end

    assert_equal 0, DB[:que_jobs].count
    DefaultRunAtJob.enqueue 1
    DefaultRunAtJob.enqueue 1, run_at: Time.now + 30
    assert_equal 2, DB[:que_jobs].count

    first, second = DB[:que_jobs].order(:job_id).all

    assert_equal 100, first[:priority]
    assert_in_delta first[:run_at], Time.now + 60, 3
    assert_equal 'DefaultRunAtJob', first[:job_class]
    assert_equal [1], JSON.load(first[:args])

    assert_equal 100, second[:priority]
    assert_in_delta second[:run_at], Time.now + 30, 3
    assert_equal 'DefaultRunAtJob', second[:job_class]

    assert_equal [1], JSON.load(second[:args])
  end
end
