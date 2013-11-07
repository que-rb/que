require 'spec_helper'

describe "Que::Job.work" do
  it "should automatically delete jobs from the database's queue" do
    Que::Job.count.should be 0
    Que::Job.queue
    Que::Job.count.should be 1
    Que::Job.work
    Que::Job.count.should be 0
  end

  it "should pass a job's arguments to its perform method" do
    class JobWorkTest < Que::Job
      def perform(*args)
        $passed_args = args
      end
    end

    JobWorkTest.queue 5, 'ferret', :lazy => true

    Que::Job.work
    $passed_args.should == [5, 'ferret', {'lazy' => true}]
  end

  it "should prefer a job with higher priority" do
    Que::Job.queue
    Que::Job.queue :priority => 1

    Que::Job.select_order_map(:priority).should == [1, 5]
    Que::Job.work
    Que::Job.select_order_map(:priority).should == [5]
  end

  it "should prefer a job that was scheduled to run longer ago" do
    now  = Time.at(Time.now.to_i) # Prevent rounding errors by rounding to the nearest second.
    recently = now - 60
    long_ago = now - 61

    Que::Job.queue :run_at => recently
    Que::Job.queue :run_at => long_ago

    Que::Job.select_order_map(:run_at).should == [long_ago, recently]
    Que::Job.work
    Que::Job.select_order_map(:run_at).should == [recently]
  end

  it "should only work a job whose run_at has already passed" do
    now  = Time.at(Time.now.to_i) # Prevent rounding errors by rounding to the nearest second.
    past = now - 60
    soon = now + 60

    Que::Job.queue :run_at => past
    Que::Job.queue :run_at => soon

    Que::Job.select_order_map(:run_at).should == [past, soon]
    Que::Job.work
    Que::Job.select_order_map(:run_at).should == [soon]
    Que::Job.work
    Que::Job.select_order_map(:run_at).should == [soon]
  end

  it "should prefer a job that was scheduled earlier, and therefore has a lower job_id" do
    time = Time.now - 60
    Que::Job.queue :run_at => time
    Que::Job.queue :run_at => time

    a, b = Que::Job.select_order_map(:job_id)
    Que::Job.work
    Que::Job.select_order_map(:job_id).should == [b]
  end

  it "should lock the job it selects" do
    $q1, $q2 = Queue.new, Queue.new

    class LockJob < Que::Job
      def perform(*args)
        $q1.push nil
        $q2.pop
      end
    end

    job = LockJob.queue
    @thread = Thread.new { Que::Job.work }

    # Wait until job is being worked.
    $q1.pop

    # Job should be advisory-locked...
    DB.select{pg_try_advisory_lock(job.job_id)}.single_value.should be false

    # ...and Job.work should ignore advisory-locked jobs.
    Que::Job.work.should be nil

    # Let LockJob finish.
    $q2.push nil

    # Make sure there aren't any errors.
    @thread.join
  end

  it "that raises a Que::Job::Retry should abort the job, leaving it to be retried" do
    class RetryJob < Que::Job
      def perform(*args)
        raise Que::Job::Retry
      end
    end

    job = RetryJob.queue
    Que::Job.count.should be 1
    Que::Job.work
    Que::Job.count.should be 1

    same_job = Que::Job.first
    same_job.job_id.should == job.job_id
    same_job.run_at.should == job.run_at
    same_job.data['error_count'].should be nil
  end

  it "should handle subclasses of other jobs" do
    $class_job_array = []

    class ClassJob < Que::Job
      def perform(*args)
        $class_job_array << 2
      end
    end

    class SubclassJob < ClassJob
      def perform(*args)
        $class_job_array << 1
        super
      end
    end

    SubclassJob.queue
    Que::Job.get(:type).should == 'SubclassJob'
    Que::Job.work
    $class_job_array.should == [1, 2]
  end
end
