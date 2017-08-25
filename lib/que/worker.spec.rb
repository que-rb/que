# frozen_string_literal: true

require 'spec_helper'

describe Que::Worker do
  let :priority do
    nil
  end

  let :worker do
    Que::Worker.new(
      priority:     priority,
      job_queue:    job_queue,
      result_queue: result_queue,
    )
  end

  let :notified_errors do
    []
  end

  before do
    worker
    Que.error_notifier = proc { |e| notified_errors << e }

    class WorkerJob < Que::Job
      def run(*args)
        $args = args
      end
    end
  end

  after do
    Object.send :remove_const, :WorkerJob
    $args = nil
  end

  def run_jobs(*jobs)
    jobs.flatten!
    jobs = jobs_dataset.all if jobs.empty?

    result_queue.clear

    jobs.map! { |job| Que::Metajob.new(job) }

    job_ids = jobs.map(&:id).sort

    job_queue.push(*jobs)

    sleep_until! do
      finished_job_ids == job_ids
    end
  end

  def finished_job_ids
    results(message_type: :job_finished).map{|m| m.fetch(:metajob).id}.sort
  end

  it "should repeatedly work jobs that are passed to it via its job_queue" do
    results = []

    WorkerJob.class_eval do
      define_method :run do |number|
        results << number
      end
    end

    [1, 2, 3].each { |i| WorkerJob.enqueue i, priority: i }
    job_ids = jobs_dataset.order_by(:priority).select_map(:id)
    run_jobs

    assert_equal [1, 2, 3], results
    assert_equal job_ids, finished_job_ids

    events = logged_messages.select{|m| m[:event] == 'job_worked'}
    assert_equal 3, events.count
    assert_equal [1, 2, 3], events.map{|m| m[:job][:priority]}
  end

  it "should handle namespaced job subclasses" do
    NamespacedJobNamespace::NamespacedJob.enqueue
    assert_equal "NamespacedJobNamespace::NamespacedJob", jobs_dataset.get(:job_class)

    run_jobs
    assert_empty active_jobs_dataset
  end

  it "should skip a job if passed a nonexistent sort key" do
    assert_equal 0, jobs_dataset.count
    attrs = Que::Job.enqueue.que_attrs
    assert_equal 1, jobs_dataset.where(id: attrs.fetch(:id)).delete

    assert_equal 0, jobs_dataset.count
    run_jobs(attrs)
    assert_equal 0, jobs_dataset.count

    assert_equal [attrs.fetch(:id)], finished_job_ids
  end

  describe "when given a priority requirement" do
    let(:priority) { 10 }

    it "should only take jobs that meet it priority requirement" do
      jobs =
        (1..20).map do |i|
          Que::Job.enqueue(i, priority: i).que_attrs
        end

      job_ids = jobs.map { |j| j[:id] }

      job_queue.push *jobs.map{|j| Que::Metajob.new(j)}

      sleep_until! { finished_job_ids == job_ids[0..9] }

      assert_equal job_ids[10..19], job_queue.to_a.map(&:id)
    end
  end

  describe "when an error is raised" do
    before do
      WorkerJob.class_eval do
        def run(*args)
          raise "Error!"
        end
      end
    end

    def assert_retry_cadence(
      *delays,
      job_class: "WorkerJob",
      expected_error_message: "Error!",
      expected_backtrace: /\A#{__FILE__}/
    )
      jobs_dataset.insert(job_class: job_class)

      error_count = 0
      delays.each do |delay|
        run_jobs
        error_count += 1

        assert_equal 1, jobs_dataset.count
        job = jobs_dataset.first
        assert_equal error_count, job[:error_count]

        if expected_error_message.is_a?(Regexp)
          assert_match expected_error_message, job[:last_error_message]
        else
          assert_equal expected_error_message, job[:last_error_message]
        end

        assert_match(
          expected_backtrace,
          job[:last_error_backtrace].split("\n").first,
        )

        assert_in_delta job[:run_at], Time.now + delay, 3

        jobs_dataset.update(run_at: Time.now - 60)
      end
    end

    it "should record/report the error and not crash the worker" do
      # First job should error, second job should still be worked.
      job_ids = [
        WorkerJob.enqueue(priority: 1),
        Que::Job.enqueue(priority: 2),
      ].map{|j| j.que_attrs[:id]}

      run_jobs
      assert_equal job_ids, finished_job_ids

      events = logged_messages.select{|m| m[:event] == 'job_errored'}
      assert_equal 1, events.count

      # Error should be logged.
      event = events.first
      assert_equal 1, event[:job][:priority]
      assert_equal job_ids.first, event[:job][:id]
      assert_equal "Error!", event[:error]

      # Errored job should still be in the DB.
      assert_equal [job_ids.first], active_jobs_dataset.select_map(:id)
      assert_equal ["Error!"], active_jobs_dataset.select_map(:last_error_message)

      # error_notifier proc should have been called.
      assert_equal 1, notified_errors.length
      assert_instance_of RuntimeError, notified_errors.first
      assert_equal "Error!", notified_errors.first.message
    end

    it "should truncate the error message if necessary" do
      WorkerJob.class_eval do
        def run(*args)
          raise "a" * 501
        end
      end

      WorkerJob.enqueue
      run_jobs

      assert_equal 1, jobs_dataset.count
      job = jobs_dataset.first
      assert_equal 1, job[:error_count]
      assert_equal "a" * 500, job[:last_error_message]
    end

    describe "when retrying because the job logic raised an error" do
      it "should exponentially back off the job, by default" do
        # Default formula is (count^4) + 3
        assert_retry_cadence 4, 19, 84, 259
      end

      it "when the retry_interval is an integer" do
        WorkerJob.class_eval { @retry_interval = 5 }
        assert_retry_cadence 5, 5, 5, 5
      end

      it "when the retry_interval is a callable returning an integer" do
        WorkerJob.class_eval { @retry_interval = proc { |count| count * 10 } }
        assert_retry_cadence 10, 20, 30, 40
      end

      it "when the retry_interval is a float" do
        WorkerJob.class_eval { @retry_interval = 4.5 }
        assert_retry_cadence 4.5, 4.5, 4.5, 4.5
      end

      it "when the retry_interval is a callable returning a float" do
        WorkerJob.class_eval { @retry_interval = proc { |count| count * 2.5 } }
        assert_retry_cadence 2.5, 5.0, 7.5, 10.0
      end

      if defined?(ActiveSupport)
        it "when the retry_interval is an ActiveSupport::Duration" do
          WorkerJob.class_eval { @retry_interval = 5.minutes }
          assert_retry_cadence 300, 300, 300, 300
        end

        it "when the retry_interval is a callable returning an ActiveSupport::Duration" do
          WorkerJob.class_eval { @retry_interval = proc { |count| count.minutes } }
          assert_retry_cadence 60, 120, 180, 240
        end
      end
    end

    describe "when retrying because the job couldn't even be run" do
      it "when there's no corresponding job class" do
        assert_retry_cadence \
          4, 19, 84, 259,
          job_class: "NonexistentClass",
          expected_error_message: /uninitialized constant:? .*NonexistentClass/,
          expected_backtrace: /in `const_get'/

        assert_instance_of NameError, notified_errors.first
      end

      it "when the job class doesn't descend from Que::Job" do
        class J
          def initialize(*args)
          end

          def run(*args)
          end
        end

        assert_retry_cadence \
          4, 19, 84, 259,
          job_class: "J",
          expected_error_message: /undefined method/,
          expected_backtrace: /que\/worker\.rb/

        assert_instance_of NoMethodError, notified_errors.first
      end
    end

    describe "when the job class has a custom error handler" do
      it "should allow it to schedule a retry after an integer interval" do
        WorkerJob.class_eval do
          private

          def handle_error(error)
            retry_in(42)
          end
        end

        assert_retry_cadence 42, 42, 42, 42

        assert_instance_of RuntimeError, notified_errors.first
        assert_equal "Error!", notified_errors.first.message
      end

      it "should allow it to schedule a retry after a float interval" do
        WorkerJob.class_eval do
          private

          def handle_error(error)
            retry_in(35.3226247635)
          end
        end

        assert_retry_cadence 35.3226247635, 35.3226247635, 35.3226247635, 35.3226247635

        assert_instance_of RuntimeError, notified_errors.first
        assert_equal "Error!", notified_errors.first.message
      end

      if defined?(ActiveSupport)
        it "should allow it to schedule a retry after a ActiveSupport::Duration" do
          WorkerJob.class_eval do
            private

            def handle_error(error)
              retry_in(5.minutes)
            end
          end

          assert_retry_cadence 300, 300, 300, 300

          assert_instance_of RuntimeError, notified_errors.first
          assert_equal "Blah!", notified_errors.first.message
        end
      end

      it "should allow it to destroy the job" do
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

        assert_instance_of RuntimeError, notified_errors.first
        assert_equal "Blah!", notified_errors.first.message
      end

      it "should allow it to return false to skip the error notification" do
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
        assert_equal 1, jobs_dataset.count
        assert_equal 0, active_jobs_dataset.count

        assert_empty notified_errors
      end

      it "should allow it to call super to get the default behavior" do
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

        assert_instance_of RuntimeError, notified_errors.first
        assert_equal "Blah!", notified_errors.first.message
      end
    end
  end
end
