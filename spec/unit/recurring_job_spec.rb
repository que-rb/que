require 'spec_helper'

describe Que::RecurringJob do
  class CronJob < Que::RecurringJob
    @interval = 60
  end

  def run_job
    job_id = DB[:que_jobs].get(:job_id)
    locker = Que::Locker.new
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

  it "should make the time range helper methods available to the run method"

  it "should reenqueue itself if it wasn't reenqueued or destroyed already"

  it "should allow its arguments to be overridden when reenqueued"

  it "should respect the @interval configuration"

  it "should allow the interval to be overridden when reenqueued"

  it "should allow @interval to be overridden in subclasses as you would expect"

  it "should throw an error on the initial enqueueing if an @interval is not set"

  it "should throw an error on the reenqueueing if an @interval is not set"
end
