# frozen_string_literal: true

require 'spec_helper'

describe "Que Jobs Ext View", skip: true do
  
  class TestJob < Que::Job
    include Que::JobMethods

    def default_resolve_action
      # prevents default deletion of complete jobs for testing purposes
      finish
    end
  end

  class TestFailedJob < TestJob
    def run 
      raise Que::Error, 'Test Error'
    end
  end

  describe 'job.enqueue' do 
    it "should mirror enqueued job" do
      assert_equal 0, jobs_dataset.count
      assert_equal 0, jobs_ext_dataset.count

      TestJob.enqueue(
          1,
          'two',
          string: "string",
          integer: 5,
          array: [1, "two", {three: 3}],
          hash: {one: 1, two: 'two', three: [3]},
          job_options: { 
            priority: 4,
            queue: 'special_queue_name',
            run_at: Time.now
          }
        )

      assert_equal 1, jobs_dataset.count
      assert_equal 1, jobs_ext_dataset.count

      job = jobs_dataset.first
      ext_job = jobs_ext_dataset.first
      assert_equal ext_job[:queue], job[:queue]
      assert_equal ext_job[:priority], job[:priority]
      assert_equal ext_job[:run_at], job[:run_at]
      assert_equal ext_job[:first_run_at], job[:first_run_at]
      assert_equal ext_job[:job_class], job[:job_class]
      assert_equal ext_job[:args], job[:args]
      assert_equal ext_job[:job_schema_version], job[:job_schema_version]   

      jobs_dataset.delete

      assert_equal 0, jobs_dataset.count
      assert_equal 0, jobs_ext_dataset.count
    end

    it "should include additional lock data" do
      locker_settings.clear
      locker_settings[:listen] = false
      locker_settings[:poll_interval] = 0.02
      locker
      
      TestJob.enqueue

      sleep_until { locked_ids.count.positive? && locked_ids.first == jobs_ext_dataset.first[:lock_id] }

      locker.stop!

      jobs_dataset.delete
    end

    it "should add additional updated_at" do
      TestJob.enqueue

      ext_job = jobs_ext_dataset.first

      assert_equal ext_job[:run_at], ext_job[:updated_at]

      locker

      sleep_until_equal(1) { finished_jobs_dataset.count }

      locker.stop!

      ext_job = jobs_ext_dataset.first

      assert_equal ext_job[:finished_at], ext_job[:updated_at]

      jobs_dataset.delete
    end

    describe "should include additional status" do
      
      let(:notified_errors) { [] }

      it "should set status to scheduled when run_at is in the future" do
        TestJob.enqueue(job_options: { run_at: Time.now + 1 })

        assert_equal jobs_ext_dataset.first[:status], 'scheduled'

        jobs_dataset.delete
      end

      it "should set status to queued when run_at is in the past and the job is not currently running, completed, failed or errored" do
        TestJob.enqueue(job_options: { run_at: Time.now - 1 })

        assert_equal jobs_ext_dataset.first[:status], 'queued'

        jobs_dataset.delete
      end

      it "should set status to running when the job has a lock associated with it" do  
        locker_settings.clear
        locker_settings[:listen] = false
        locker_settings[:poll_interval] = 0.02
        locker

        TestJob.enqueue

        sleep_until { locked_ids.count.positive? && locked_ids.first == jobs_ext_dataset.first[:lock_id] && jobs_ext_dataset.first[:status] == 'running' }

        locker.stop!

        jobs_dataset.delete
      end

      it "should set status to complete when finished_at is present" do
        TestJob.enqueue

        locker
        
        sleep_until_equal(1) { DB[:que_lockers].count }

        sleep_until { finished_jobs_dataset.count.positive? }

        locker.stop!
        
        assert_equal jobs_ext_dataset.first[:status], 'completed'

        jobs_dataset.delete
      end

      it "should set status to errored when error_count is positive and expired_at is not present" do
        Que.error_notifier = proc { |e| notified_errors << e }

        TestFailedJob.class_eval do 
          self.maximum_retry_count = 100 # prevent from entering failed state on first error
        end

        locker
        
        sleep_until_equal(1) { DB[:que_lockers].count }

        TestFailedJob.enqueue

        sleep_until { errored_jobs_dataset.where(expired_at: nil).count.positive? }

        locker.stop!

        ext_job = jobs_ext_dataset.first

        assert_equal ext_job[:status], 'errored'
        assert_equal notified_errors.count, 1
        assert_equal notified_errors.first.message, 'Test Error'


        jobs_dataset.delete
      end

      it "should set status to failed when expired_at is present" do
        TestFailedJob.class_eval do 
          self.maximum_retry_count = 0
        end

        Que.error_notifier = proc { |e| notified_errors << e }

        locker
        
        sleep_until_equal(1) { DB[:que_lockers].count }

        TestFailedJob.enqueue

        sleep_until { expired_jobs_dataset.count.positive? }

        locker.stop!

        assert_equal jobs_ext_dataset.first[:status], 'failed'
        assert_equal notified_errors.count, 1
        assert_equal notified_errors.first.message, 'Test Error'


        jobs_dataset.delete
      end
    end
  end
end