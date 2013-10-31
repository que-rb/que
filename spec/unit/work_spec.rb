require 'spec_helper'

describe "Job.work" do
  it "should pass a job's arguments to its perform method and delete it from the DB" do
    class JobWorkTest < Job
      def perform(*args)
        $passed_args = args
      end
    end

    JobWorkTest.queue 5, 'ferret', :lazy => true

    Que::Job.count.should be 1
    Que::Job.work
    Que::Job.count.should be 0
    $passed_args.should == [5, 'ferret', {:lazy => true}.with_indifferent_access]
  end

  it "should prefer a job with higher priority" do
    Que::Job.queue
    Que::Job.queue :priority => 1

    Que::Job.select_order_map(:priority).should == [1, 5]
    Que::Job.work
    Que::Job.select_order_map(:priority).should == [5]
  end

  it "should prefer a job that was scheduled to run longer ago" do
    long_ago = 1.week.ago.change(:usec => 500000) # Prevent rounding errors.
    recently = 1.day.ago.change(:usec => 500000)

    Que::Job.queue :run_at => long_ago
    Que::Job.queue :run_at => recently

    Que::Job.select_order_map(:run_at).should == [long_ago, recently]
    Que::Job.work
    Que::Job.select_order_map(:run_at).should == [recently]
  end

  it "should only work a job whose run_at has already passed" do
    past = 1.week.ago.change(:usec => 500000) # Prevent rounding errors.
    soon = 1.day.from_now.change(:usec => 500000)

    Que::Job.queue :run_at => past
    Que::Job.queue :run_at => soon

    Que::Job.select_order_map(:run_at).should == [past, soon]
    Que::Job.work
    Que::Job.select_order_map(:run_at).should == [soon]
    Que::Job.work
    Que::Job.select_order_map(:run_at).should == [soon]
  end

  it "should prefer a job that was scheduled earlier, and therefore has a lower job_id" do
    time = 1.day.ago
    Que::Job.queue :run_at => time
    Que::Job.queue :run_at => time

    a, b = Que::Job.select_order_map(:job_id)
    Que::Job.work
    Que::Job.select_order_map(:job_id).should == [b]
  end

  it "should lock the job it selects" do
    $q1, $q2 = Queue.new, Queue.new

    class SleepJob < Que::Job
      def perform(*args)
        $q1.push nil
        $q2.pop
      end
    end

    SleepJob.queue
    @thread = Thread.new { Que::Job.work }

    $q1.pop
    sleep_until { Que::Job.work.nil? }

    $q2.push nil
    @thread.join # Make sure there aren't any errors.
  end

  it "should skip jobs that are advisory locked" do
    job    = Que::Job.queue
    main   = Thread.current
    locked = false

    thread = Thread.new do
      DB.transaction do
        DB.select{pg_advisory_xact_lock(job.job_id)}.single_value
        locked = true
        main.wakeup
        Thread.stop
      end
    end

    Thread.stop unless locked

    Que::Job.work.should be nil
    thread.wakeup
    thread.join
    Que::Job.work.should == job.tap { |job| job[:locked] = true }
  end

  it "that raises a Job::Retry should cancel the job, leaving it to be retried" do
    class RetryJob < Que::Job
      def perform(*args)
        raise Job::Retry
      end
    end

    job = RetryJob.queue
    Que::Job.count.should be 1
    Que::Job.work
    Que::Job.count.should be 1

    same_job = Que::Job.first
    same_job.job_id.should == job.job_id
    same_job.run_at.should be_within(1.second).of Time.now
    same_job.data[:error_count].should be nil
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
