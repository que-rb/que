require 'spec_helper'

describe Que::RecurringJob do
  class CronJob < Que::RecurringJob
    @interval = 60
  end

  def run_job
    job_id = DB[:que_jobs].get(:job_id)
    locker = Que::Locker.new poll_interval: 0.01 # For jobs that error.
    sleep_until { DB[:que_jobs].where(job_id: job_id).empty? }
    locker.stop
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

      t_ii, t_if = $initial[:args][-1].delete(:recurring_interval)
      t_fi, t_ff = $final[:args][-1].delete(:recurring_interval)

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

  it "shouldn't allow any mutation of the args hash to be propagated to the next job"

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

      t_i, t_f = $from_db[:args][-1][:recurring_interval]

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
    ensure
      $start_times = $end_times = $time_ranges = $next_run_times = $from_dbs = $run_count = nil
    end
  end

  it "should reenqueue itself if it wasn't reenqueued or destroyed already" do
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

  it "should allow its arguments to be overridden when reenqueued"

  it "should respect the @interval configuration"

  it "should allow the interval to be overridden when reenqueued"

  it "should allow @interval to be overridden in subclasses as you would expect"

  it "should throw an error on the initial enqueueing if an @interval is not set"

  it "should throw an error on the reenqueueing if an @interval is not set"
end
