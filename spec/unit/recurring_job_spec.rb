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

  it "should support being reenqueued in a transaction" do
    enqueued = CronJob.enqueue 1, 'a', {opt: 45}

    begin
      class CronJob
        def run(*args)
          $passed_to_cron = args

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
      $final[:run_at].should == $initial[:run_at] + 60
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

  it "should make the time range helper methods available to the run method"

  it "should reenqueue by default with the same arguments"

  it "should reenqueue itself if it wasn't reenqueued or destroyed already"

  it "should allow its arguments to be overridden when reenqueued"

  it "should respect the @interval configuration"

  it "should allow the interval to be overridden when reenqueued"

  it "should allow @interval to be overridden in subclasses as you would expect"

  it "should throw an error on the initial enqueueing if an @interval is not set"

  it "should throw an error on the reenqueueing if an @interval is not set"
end
