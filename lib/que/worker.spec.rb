# frozen_string_literal: true

require 'spec_helper'

describe Que::Worker do
  let :priority do
    nil
  end

  let :job_queue do
    Que::JobQueue.new(maximum_size: 20)
  end

  let :result_queue do
    Que::ResultQueue.new
  end

  let :worker do
    Que::Worker.new(
      priority:     priority,
      job_queue:    job_queue,
      result_queue: result_queue,
    )
  end

  before { worker }

  def run_jobs(*jobs)
    jobs.flatten!
    jobs = jobs_dataset.all if jobs.empty?

    result_queue.clear

    jobs.map! do |job|
      {
        queue:    job[:queue],
        priority: job[:priority],
        run_at:   job[:run_at],
        id:       job[:id],
      }
    end

    job_ids = jobs.map{|j| j[:id]}.sort

    job_queue.push(*jobs)

    sleep_until do
      result_queue.length == job_ids.length &&
      result_queue.to_a.sort == job_ids
    end
  end

  it "should repeatedly work jobs that are passed to it via its job_queue" do
    begin
      $results = []

      class WorkerJob < Que::Job
        def run(number)
          $results << number
        end
      end

      [1, 2, 3].each { |i| WorkerJob.enqueue i, priority: i }
      job_ids = jobs_dataset.order_by(:priority).select_map(:id)
      run_jobs

      assert_equal [1, 2, 3], $results
      assert_equal job_ids, result_queue.to_a

      events = logged_messages.select{|m| m[:event] == 'job_worked'}
      assert_equal 3, events.count
      assert_equal [1, 2, 3], events.map{|m| m[:job][:priority]}
    ensure
      $results = nil
    end
  end

  it "should handle namespaced job subclasses" do
    begin
      $run = false

      # TODO: Use the namespaced job in the support folder for this?
      module ModuleJobModule
        class ModuleJob < Que::Job
          def run
            $run = true
          end
        end
      end

      ModuleJobModule::ModuleJob.enqueue
      assert_equal "ModuleJobModule::ModuleJob", jobs_dataset.get(:job_class)

      run_jobs
      assert_equal true, $run
    ensure
      $run = nil
    end
  end

  it "should skip a job if passed a nonexistent sort key" do
    assert_equal 0, jobs_dataset.count
    run_jobs queue:    'default',
             priority: 1,
             run_at:   Time.now,
             id:       587648

    assert_equal [587648], result_queue.to_a
  end

  describe "when given a priority requirement" do
    let(:priority) { 10 }

    it "should only take jobs that meet it priority requirement" do
      jobs = (1..20).map { |i| {priority: i, run_at: Time.now, id: i} }

      job_queue.push *jobs

      sleep_until { result_queue.to_a == (1..10).to_a }

      assert_equal jobs[10..19], job_queue.to_a
    end
  end

  it "should run the start_callback if passed one" do
    skip "Probably want to implement full-fledged callbacks around worker start and working jobs"
  end

  describe "when an error is raised" do
    it "should not crash the worker" do
      ErrorJob.enqueue priority: 1
      Que::Job.enqueue priority: 2

      job_ids = jobs_dataset.order_by(:priority).select_map(:id)
      run_jobs
      assert_equal job_ids, result_queue.to_a

      events = logged_messages.select{|m| m[:event] == 'job_errored'}
      assert_equal 1, events.count

      event = events.first
      assert_equal 1, event[:job][:priority]
      assert_kind_of Integer, event[:job][:id]
      assert_equal "ErrorJob!", event[:error]
    end

    it "should pass it to the error notifier" do
      error = nil
      Que.error_notifier = proc { |e| error = e }

      ErrorJob.enqueue priority: 1

      run_jobs

      assert_instance_of RuntimeError, error
      assert_equal "ErrorJob!", error.message
    end

    it "should exponentially back off the job" do
      ErrorJob.enqueue

      run_jobs

      assert_equal 1, jobs_dataset.count
      job = jobs_dataset.first
      assert_equal 1, job[:error_count]
      assert_equal "ErrorJob!", job[:last_error_message]
      assert_match(
        /support\/jobs\/error_job/,
        job[:last_error_backtrace].split("\n").first,
      )
      assert_in_delta job[:run_at], Time.now + 4, 3

      jobs_dataset.update error_count: 5,
                          run_at:      Time.now - 60

      run_jobs

      assert_equal 1, jobs_dataset.count
      job = jobs_dataset.first
      assert_equal 6, job[:error_count]
      assert_equal "ErrorJob!", job[:last_error_message]
      assert_match(
        /support\/jobs\/error_job/,
        job[:last_error_backtrace].split("\n").first,
      )
      assert_in_delta job[:run_at], Time.now + 1299, 3
    end

    it "should respect a custom retry interval" do
      class RetryIntervalJob < ErrorJob
        @retry_interval = 5
      end

      RetryIntervalJob.enqueue

      run_jobs

      assert_equal 1, jobs_dataset.count
      job = jobs_dataset.first

      assert_equal 1, job[:error_count]
      assert_equal "ErrorJob!", job[:last_error_message]
      assert_match(
        /support\/jobs\/error_job/,
        job[:last_error_backtrace].split("\n").first,
      )
      assert_in_delta job[:run_at], Time.now + 5, 3

      jobs_dataset.update error_count: 5,
                          run_at:      Time.now - 60

      run_jobs

      assert_equal 1, jobs_dataset.count
      job = jobs_dataset.first

      assert_equal 6, job[:error_count]
      assert_equal "ErrorJob!", job[:last_error_message]
      assert_match(
        /support\/jobs\/error_job/,
        job[:last_error_backtrace].split("\n").first,
      )
      assert_in_delta job[:run_at], Time.now + 5, 3
    end

    it "should respect a custom retry interval formula" do
      class RetryIntervalFormulaJob < ErrorJob
        @retry_interval = proc { |count| count * 10 }
      end

      RetryIntervalFormulaJob.enqueue

      run_jobs

      assert_equal 1, jobs_dataset.count
      job = jobs_dataset.first
      assert_equal 1, job[:error_count]
      assert_equal "ErrorJob!", job[:last_error_message]
      assert_match(
        /support\/jobs\/error_job/,
        job[:last_error_backtrace].split("\n").first,
      )
      assert_in_delta job[:run_at], Time.now + 10, 3

      jobs_dataset.update error_count: 5,
                          run_at:      Time.now - 60

      run_jobs

      assert_equal 1, jobs_dataset.count
      job = jobs_dataset.first
      assert_equal 6, job[:error_count]
      assert_equal "ErrorJob!", job[:last_error_message]
      assert_match(
        /support\/jobs\/error_job/,
        job[:last_error_backtrace].split("\n").first,
      )
      assert_in_delta job[:run_at], Time.now + 60, 3
    end

    it "should throw an error properly if there's no corresponding job class" do
      error = nil
      Que.error_notifier = proc { |e| error = e }

      jobs_dataset.insert job_class: "NonexistentClass"

      run_jobs

      assert_equal 1, jobs_dataset.count
      job = jobs_dataset.first
      assert_equal 1, job[:error_count]
      assert_match /uninitialized constant:? .*NonexistentClass/,
        job[:last_error_message]
      assert_in_delta job[:run_at], Time.now + 4, 3

      assert_instance_of NameError, error
    end

    it "should throw an error if the job class doesn't descend from Que::Job" do
      error = nil
      Que.error_notifier = proc { |e| error = e }

      class J
        def initialize(*args)
        end

        def run(*args)
        end
      end

      Que.enqueue job_class: "J"

      run_jobs

      assert_equal 1, jobs_dataset.count
      job = jobs_dataset.first
      assert_equal 1, job[:error_count]
      assert_in_delta job[:run_at], Time.now + 4, 3

      assert_instance_of NoMethodError, error
    end

    describe "in a job class that has a custom error handler" do
      it "should allow it to schedule a retry after a specific interval" do
        error = nil
        Que.error_notifier = proc { |e| error = e }

        class CustomRetryIntervalJob < Que::Job
          def run(*args)
            raise "Blah!"
          end

          private

          def handle_error(error)
            retry_in(42)
          end
        end

        CustomRetryIntervalJob.enqueue

        run_jobs

        assert_equal 1, jobs_dataset.count
        job = jobs_dataset.first
        assert_equal 1, job[:error_count]
        assert_match /\ABlah!/, job[:last_error_message]
        assert_match(
          /worker\.spec\.rb/,
          job[:last_error_backtrace].split("\n").first,
        )
        assert_in_delta job[:run_at], Time.now + 42, 3

        assert_instance_of RuntimeError, error
        assert_equal "Blah!", error.message
      end

      it "should allow it to destroy the job" do
        error = nil
        Que.error_notifier = proc { |e| error = e }

        class CustomRetryIntervalJob < Que::Job
          def run(*args)
            raise "Blah!"
          end

          private

          def handle_error(error)
            destroy
          end
        end

        CustomRetryIntervalJob.enqueue

        assert_equal 1, jobs_dataset.count
        run_jobs
        assert_equal 0, jobs_dataset.count

        assert_instance_of RuntimeError, error
        assert_equal "Blah!", error.message
      end

      it "should allow it to return false to skip the error notification" do
        error = nil
        Que.error_notifier = proc { |e| error = e }

        class CustomRetryIntervalJob < Que::Job
          def run(*args)
            raise "Blah!"
          end

          private

          def handle_error(error)
            false
          end
        end

        CustomRetryIntervalJob.enqueue

        assert_equal 1, jobs_dataset.count
        run_jobs
        assert_equal 0, jobs_dataset.count

        assert_nil error
      end

      it "should allow it to call super to get the default behavior" do
        error = nil
        Que.error_notifier = proc { |e| error = e }

        class CustomRetryIntervalJob < Que::Job
          def run(*args)
            raise "Blah!"
          end

          private

          def handle_error(error)
            case error
            when RuntimeError
              super
            else
              $error_handler_failed = true
              raise "Bad!"
            end
          end
        end

        CustomRetryIntervalJob.enqueue
        run_jobs
        assert_nil $error_handler_failed

        assert_equal 1, jobs_dataset.count
        job = jobs_dataset.first
        assert_equal 1, job[:error_count]
        assert_match /\ABlah!/, job[:last_error_message]
        assert_match(
          /worker\.spec\.rb/,
          job[:last_error_backtrace].split("\n").first,
        )
        assert_in_delta job[:run_at], Time.now + 4, 3

        assert_instance_of RuntimeError, error
        assert_equal "Blah!", error.message
      end
    end
  end
end
