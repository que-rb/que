# frozen_string_literal: true

require 'spec_helper'

describe Que::RecurringJob do
  class CronJob < Que::RecurringJob
  end

  def run_job
    job_id = DB[:que_jobs].get(:job_id)
    locker = Que::Locker.new poll_interval: 0.01 # For jobs that error.
    sleep_until { DB[:que_jobs].where(job_id: job_id).empty? }
    locker.stop!
  end

  before do
    class CronJob
      @interval = 60

      def run(*args)
      end
    end
  end

  it "should support being reenqueued in a transaction with the same arguments" do
    enqueued = CronJob.enqueue 1, 'a', {opt: 45}

    begin
      class CronJob
        def run(*args)
          $passed_to_cron = args.dup

          Que.transaction do
            $initial = Que.execute("SELECT * FROM que_jobs LIMIT 1").first
            reenqueue
            $final = Que.execute("SELECT * FROM que_jobs LIMIT 1").first
          end
        end
      end

      run_job

      $initial[:job_id].should == enqueued.attrs[:job_id]
      $initial[:run_at].should == enqueued.attrs[:run_at]

      $passed_to_cron.should == [1, 'a', {opt: 45}]
      $final[:job_id].should be > $initial[:job_id]

      t_ii, t_if = $initial[:args][0].delete(:recurring_interval)
      t_fi, t_ff = $final[:args][0].delete(:recurring_interval)

      $final[:run_at].to_f.round(6).should be_within(0.000001).of(t_ff)

      t_ii.should == t_if - 60
      t_if.should == t_fi
      t_fi.should == t_ff - 60

      $final[:args].should == $initial[:args]
    ensure
      $initial = $final = $passed_to_cron = nil
    end
  end

  it "should support simply being destroyed" do
    enqueued = CronJob.enqueue 1, 'a', {opt: 45}

    begin
      class CronJob
        def run(*args)
          Que.transaction do
            $initial = Que.execute("SELECT * FROM que_jobs LIMIT 1").first
            destroy
            $final = Que.execute("SELECT * FROM que_jobs LIMIT 1").first
          end
        end
      end

      run_job

      $final.should be nil

      $initial[:job_id].should == enqueued.attrs[:job_id]
      $initial[:run_at].should == enqueued.attrs[:run_at]
    ensure
      $initial = $final = nil
    end
  end

  it "shouldn't allow any mutation of the args hash to be propagated to the next job" do
    enqueued = CronJob.enqueue 1, 'a', {opt: 45}

    begin
      class CronJob
        def run(*args)
          $passed_args = JSON.parse(JSON.dump(args), symbolize_names: true)
          args[-1][:opt] = 3525
          args << 'blah'
        end
      end

      run_job
      $passed_args.should == [1, 'a', {opt: 45}]
      DB[:que_jobs].update(run_at: Time.now - 60)
      run_job
      $passed_args.should == [1, 'a', {opt: 45}]
    ensure
      $passed_args = nil
    end
  end

  it "should make the time range helper methods available to the run method" do
    enqueued = CronJob.enqueue 1, 'a', {opt: 45}

    begin
      class CronJob
        def run(*args)
          $from_db = Que.execute("SELECT * FROM que_jobs LIMIT 1").first
          $start_time = start_time
          $end_time = end_time
          $time_range = time_range # start_time...end_time
          $next_run_time = next_run_time
        end
      end

      run_job

      t_i, t_f = $from_db[:args][0][:recurring_interval]

      $start_time.should == Time.at(t_i)
      $end_time.should == Time.at(t_f)
      $time_range.should == ($start_time...$end_time)
      $next_run_time.should == $end_time + 60
    ensure
      $from_db = $start_time = $end_time = $time_range = $next_run_time = nil
    end
  end

  it "shouldn't allow its timings to be thrown off by errors" do
    enqueued = CronJob.enqueue 1, 'a', {opt: 45}

    begin
      $run_count = 0
      $from_dbs = []
      $start_times = []
      $end_times = []
      $time_ranges = []
      $next_run_times = []

      class CronJob
        @retry_interval = 0

        def run(*args)
          $run_count += 1
          $from_dbs << Que.execute("SELECT * FROM que_jobs LIMIT 1").first
          $start_times << start_time
          $end_times << end_time
          $time_ranges << time_range # start_time...end_time
          $next_run_times << next_run_time
          raise if $run_count == 1
        end
      end

      run_job

      [$start_times, $end_times, $time_ranges, $next_run_times].each do |a, b|
        a.should == b
      end

      $from_dbs[0][:args].should == $from_dbs[1][:args]
      DB[:que_jobs].get(:run_at).should be_within(0.000001).of($next_run_times[1])
    ensure
      $start_times = $end_times = $time_ranges = $next_run_times = $from_dbs = $run_count = nil
    end
  end

  it "should reenqueue itself automatically if it isn't done manually" do
    enqueued = CronJob.enqueue 1, 'a', {opt: 45}

    begin
      class CronJob
        def run(*args)
          $next_run_time = next_run_time
        end
      end

      run_job

      final = DB[:que_jobs].first
      final[:job_id].should be > enqueued.attrs[:job_id]
      final[:run_at].should be_within(0.000001).of($next_run_time)
    ensure
      $next_run_time = nil
    end
  end

  it "should not reenqueue itself if it is manually destroyed" do
    enqueued = CronJob.enqueue 1, 'a', {opt: 45}

    class CronJob
      def run(*args)
        destroy
      end
    end

    run_job

    DB[:que_jobs].count.should be 0
  end

  it "should support RecurringJob.run" do
    # Don't know why someone would do this, but want to make sure the expected behavior happens.
    begin
      class CronJob
        def run(*args)
          $args = args
          $from_db = Que.execute("SELECT * FROM que_jobs LIMIT 1").first
          $start_time = start_time
          $end_time = end_time
          $time_range = time_range # start_time...end_time
          $next_run_time = next_run_time
        end
      end

      CronJob.run(456, 'blah', ferret: true)

      $args.should == [456, 'blah', {ferret: true}]
      $from_db.should == nil
      $end_time.should be_within(5).of(Time.now)
      $end_time.should == $start_time + 60
      $time_range.should == ($start_time...$end_time)
      $next_run_time.should == $end_time + 60
    ensure
      $args = $from_db = $start_time = $end_time = $time_range = $next_run_time = nil
    end
  end

  it "should use a custom run_at as the final value in the interval" do
    begin
      class CronJob
        def run(*args)
          $args = args
          $start_time = start_time
          $end_time = end_time
          $time_range = time_range # start_time...end_time
          $next_run_time = next_run_time
        end
      end

      t = Time.now - 30
      CronJob.enqueue(456, 'blah', ferret: true, run_at: t)

      run_job

      $args.should == [456, 'blah', {ferret: true}]
      $end_time.should be_within(0.000001).of(t)
      $end_time.should == $start_time + 60
      $time_range.should == ($start_time...$end_time)
      $next_run_time.should == $end_time + 60
    ensure
      $args = $from_db = $start_time = $end_time = $time_range = $next_run_time = nil
    end
  end

  it "should respect the @interval configuration" do
    begin
      class CronJob
        @interval = 5000
        def run(*args)
          $next_run_time = next_run_time
        end
      end

      t = Time.now.utc - 30
      next_time = t + 5000
      CronJob.enqueue(456, 'blah', ferret: true, run_at: t)

      DB[:que_jobs].get(:run_at).utc.should be_within(0.000002).of(t)
      run_job

      $next_run_time.utc.should be_within(0.000002).of(next_time)
      DB[:que_jobs].get(:run_at).should be_within(0.000002).of(next_time)
    ensure
      $next_run_time = nil
    end
  end

  it "should allow @interval to be overridden in subclasses as one would expect" do
    begin
      class CronJob
        @interval = 5000
        def run(*args)
          $next_run_time = next_run_time
        end
      end

      class SubCronJob < CronJob
        @interval = 70
      end

      t = Time.now.utc - 30
      next_time = t + 5000
      CronJob.enqueue(456, 'blah', ferret: true, run_at: t)

      DB[:que_jobs].get(:run_at).utc.should be_within(0.000002).of(t)
      run_job

      $next_run_time.utc.should be_within(0.000002).of(next_time)
      DB[:que_jobs].get(:run_at).should be_within(0.000002).of(next_time)
      DB[:que_jobs].delete

      next_time = t + 70
      SubCronJob.enqueue(456, 'blah', ferret: true, run_at: t)

      DB[:que_jobs].get(:run_at).utc.should be_within(0.000002).of(t)
      run_job

      $next_run_time.utc.should be_within(0.000002).of(next_time)
      DB[:que_jobs].get(:run_at).should be_within(0.000002).of(next_time)
    ensure
      $next_run_time = nil
    end
  end

  it "should throw an error on the initial enqueueing if an @interval is not set" do
    class CronJob
      @interval = nil
    end

    proc { CronJob.enqueue }.should raise_error Que::Error, "Can't enqueue a recurring job (CronJob) unless an interval is set!"
  end

  it "should throw an error on the reenqueueing if an @interval is not set" do
    CronJob.enqueue

    class CronJob
      @interval = nil
    end

    locker = Que::Locker.new
    sleep_until { DB[:que_jobs].where(error_count: 0).empty? }
    locker.stop!

    job = DB[:que_jobs].first
    job[:last_error].should =~ /Can't enqueue a recurring job \(CronJob\) unless an interval is set!/
  end

  it "should allow its arguments to be overridden when reenqueued" do
    class CronJob
      def run(count)
        reenqueue args: [count + 1]
      end
    end

    CronJob.enqueue 1

    locker = Que::Locker.new
    run_job
    locker.stop!

    job = DB[:que_jobs].first
    JSON.parse(job[:args])[-1].should == 2
  end

  it "should allow the interval to be overridden when reenqueued" do
    begin
      class CronJob
        def run
          $end_time = end_time
          reenqueue interval: 352708
        end
      end

      CronJob.enqueue

      locker = Que::Locker.new
      run_job
      locker.stop!

      job = DB[:que_jobs].first
      job[:run_at].should be_within(5).of(Time.now + 352708)
      args = JSON.parse(job[:args])

      a, b = args[0]['recurring_interval']
      b.should == a + 352708
    ensure
      $end_time = nil
    end
  end
end
