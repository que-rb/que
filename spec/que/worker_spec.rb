# frozen_string_literal: true

require 'spec_helper'

describe Que::Worker do
  let :priority do
    nil
  end

  let :worker do
    Que::Worker.new(
      priority:     priority,
      job_buffer:    job_buffer,
      result_queue: result_queue,
    )
  end

  let :notified_errors do
    []
  end

  before do
    worker
    Que.error_notifier = proc { |e, j| notified_errors.push(error: e, job: j) }

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

    job_buffer.push(*jobs)

    sleep_until timeout: 10 do
      finished_job_ids == job_ids
    end
  end

  def finished_job_ids
    results(message_type: :job_finished).map{|m| m.fetch(:metajob).id}.sort
  end

  it "should repeatedly work jobs that are passed to it via its job_buffer" do
    results = []

    WorkerJob.class_eval do
      define_method :run do |number|
        results << number
      end
    end

    [1, 2, 3].each { |i| WorkerJob.enqueue(i, job_options: { priority: i }) }
    job_ids = jobs_dataset.order_by(:priority).select_map(:id)
    run_jobs

    assert_equal [1, 2, 3], results
    assert_equal job_ids, finished_job_ids

    events = logged_messages.select{|m| m[:event] == 'job_worked'}
    assert_equal 3, events.count
    assert_equal [1, 2, 3], events.map{|m| m.dig(:job, :priority) }
    assert_equal job_ids, events.map{|m| m.dig(:job, :id) }
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

  describe "logging the job's completion" do
    def run_a_job
      WorkerJob.enqueue
      run_jobs
    end

    def assert_logging(event:, level:)
      run_a_job
      msg, actual_level = QUE_LOGGER.messages_with_levels.first
      msg = JSON.parse(msg)
      assert_equal event, msg['event']
      assert_equal level, actual_level
      msg
    end

    it "should default to logging at the debug level" do
      assert_logging(event: 'job_worked', level: :debug)
    end

    it "should use the output of log_level if it is defined" do
      WorkerJob.class_eval do
        def log_level(elapsed)
          :warn
        end
      end

      assert_logging(event: 'job_worked', level: :warn)
    end

    it "should not log if log_level doesn't return a valid level" do
      WorkerJob.class_eval do
        def log_level(elapsed)
          :blah
        end
      end

      run_a_job
      assert_empty QUE_LOGGER.messages
    end

    it "should log at the error level if the job fails" do
      WorkerJob.class_eval do
        def run(*args)
          raise "Blah!"
        end
      end

      msg = assert_logging(event: 'job_errored', level: :error)
      assert_equal "RuntimeError: Blah!", msg['error']
    end
  end

  describe "when given a priority requirement" do
    let(:priority) { 10 }

    it "should only take jobs that meet it priority requirement" do
      jobs =
        (1..20).map do |i|
          Que::Job.enqueue(i, job_options: { priority: i }).que_attrs
        end

      job_ids = jobs.map { |j| j[:id] }

      job_buffer.push *jobs.map{|j| Que::Metajob.new(j)}

      sleep_until_equal(job_ids[0..9]) { finished_job_ids }

      assert_equal job_ids[10..19], job_buffer.to_a.map(&:id)
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
      expected_error_message: "RuntimeError: Error!",
      expected_backtrace: /\A#{__FILE__}/
    )
      jobs_dataset.insert(job_class: job_class, job_schema_version: Que.job_schema_version)

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

        if expected_backtrace
          assert_match(
            expected_backtrace,
            job[:last_error_backtrace].split("\n").first,
          )
        end

        assert_in_delta job[:run_at], Time.now + delay, QueSpec::TIME_SKEW

        jobs_dataset.update(run_at: Time.now - 60)
      end
    end

    it "should record/report the error and not crash the worker" do
      # First job should error, second job should still be worked.
      job_ids = [
        WorkerJob.enqueue(job_options: { priority: 1 }),
        Que::Job.enqueue(job_options: { priority: 2 }),
      ].map{|j| j.que_attrs[:id]}

      run_jobs
      assert_equal job_ids, finished_job_ids

      events = logged_messages.select{|m| m[:event] == 'job_errored'}
      assert_equal 1, events.count

      # Error should be logged.
      event = events.first
      assert_equal job_ids.first, event.dig(:job, :id)
      assert_equal "RuntimeError: Error!", event[:error]

      # Errored job should still be in the DB.
      assert_equal [job_ids.first], active_jobs_dataset.select_map(:id)
      assert_equal ["RuntimeError: Error!"], active_jobs_dataset.select_map(:last_error_message)

      # error_notifier proc should have been called.
      assert_equal 1, notified_errors.length
      assert_instance_of RuntimeError, notified_errors.first[:error]
      assert_equal "Error!", notified_errors.first[:error].message

      job = notified_errors.first[:job]
      assert_instance_of Hash, job
      assert_equal job_ids.first, job[:id]
      assert_equal "WorkerJob", job[:job_class]
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
      assert_equal "RuntimeError: " + "a" * 486, job[:last_error_message]
    end

    describe "when retrying because the job logic raised an error" do
      it "should exponentially back off the job, by default" do
        # Default formula is (count^4) + 3
        assert_retry_cadence 4, 19, 84, 259
      end

      it "when the retry_interval is an integer" do
        WorkerJob.retry_interval = 5
        assert_retry_cadence 5, 5, 5, 5
      end

      it "when the retry_interval is a callable returning an integer" do
        WorkerJob.retry_interval = proc { |count| count * 10 }
        assert_retry_cadence 10, 20, 30, 40
      end

      it "when the retry_interval is a float" do
        WorkerJob.retry_interval = 4.5
        assert_retry_cadence 4.5, 4.5, 4.5, 4.5
      end

      it "when the retry_interval is a callable returning a float" do
        WorkerJob.retry_interval = proc { |count| count * 2.5 }
        assert_retry_cadence 2.5, 5.0, 7.5, 10.0
      end

      if defined?(ActiveSupport)
        it "when the retry_interval is an ActiveSupport::Duration" do
          WorkerJob.retry_interval = 5.minutes
          assert_retry_cadence 300, 300, 300, 300
        end

        it "when the retry_interval is a callable returning an ActiveSupport::Duration" do
          WorkerJob.retry_interval = proc { |count| count.minutes }
          assert_retry_cadence 60, 120, 180, 240
        end
      end

      describe "when the job has reached it's maximum_retry_count" do
        before do
          WorkerJob.class_eval do
            def run(*args)
              raise "Blah!"
            end
          end
        end

        it "should mark the job as expired" do
          job = WorkerJob.enqueue

          assert_equal 1, jobs_dataset.update(error_count: 14)
          # The job has failed 14 times, it's on its 14th retry.

          run_jobs

          assert_equal [[nil, 15]], jobs_dataset.select_map([:expired_at, :error_count])

          assert_equal 1, jobs_dataset.update(run_at: Time.now - 3600)

          run_jobs

          a = jobs_dataset.select_map([:expired_at, :error_count])
          assert_equal 1, a.length

          expired_at, error_count = a.first

          assert_in_delta expired_at, Time.now, QueSpec::TIME_SKEW
          assert_equal 16, error_count
        end

        describe "when that value is custom" do
          before do
            WorkerJob.maximum_retry_count = 3
          end

          it "should mark the job as expired" do
            job = WorkerJob.enqueue
            ds = jobs_dataset.where(id: job.que_attrs[:id])

            (1..4).each do |attempt|
              run_jobs
              assert_equal attempt, ds.get(:error_count)

              if attempt == 4
                assert_in_delta ds.get(:expired_at), Time.now, QueSpec::TIME_SKEW
              else
                assert_nil ds.get(:expired_at)
              end
            end
          end
        end
      end
    end

    describe "when retrying because the job couldn't even be run" do
      describe "when there's no corresponding job class" do
        it "should retry" do
          assert_retry_cadence \
            4, 19, 84, 259,
            job_class: "NonexistentClass",
            expected_error_message: /uninitialized constant:? .*NonexistentClass/,
            expected_backtrace: false

          assert_instance_of NameError, notified_errors.first[:error]
        end

        it "when it reaches a maximum should mark the job as expired" do
          job = Que.enqueue(job_options: { job_class: "NonexistentJobClass" })
          ds = jobs_dataset.where(id: job.que_attrs[:id])

          assert_equal 1, ds.update(error_count: 15)
          run_jobs

          expired_at, error_count = ds.select_map([:expired_at, :error_count]).first
          assert_in_delta expired_at, Time.now, QueSpec::TIME_SKEW
          assert_equal 16, error_count
        end
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
          expected_backtrace: false

        assert_instance_of NoMethodError, notified_errors.first[:error]
      end
    end

    describe "when the job class has a custom error handler" do
      it "should allow it to schedule a retry after an integer interval" do
        WorkerJob.class_eval do
          def handle_error(error)
            retry_in(42)
          end
        end

        assert_retry_cadence 42, 42, 42, 42

        assert_instance_of RuntimeError, notified_errors.first[:error]
        assert_equal "Error!", notified_errors.first[:error].message
      end

      it "should allow it to schedule a retry after a float interval" do
        WorkerJob.class_eval do
          def handle_error(error)
            retry_in(35.3226247635)
          end
        end

        assert_retry_cadence 35.3226247635, 35.3226247635, 35.3226247635, 35.3226247635

        assert_instance_of RuntimeError, notified_errors.first[:error]
        assert_equal "Error!", notified_errors.first[:error].message
      end

      if defined?(ActiveSupport)
        it "should allow it to schedule a retry after a ActiveSupport::Duration" do
          WorkerJob.class_eval do
            def handle_error(error)
              retry_in(5.minutes)
            end
          end

          assert_retry_cadence 300, 300, 300, 300

          assert_instance_of RuntimeError, notified_errors.first[:error]
          assert_equal "Error!", notified_errors.first[:error].message
        end
      end

      it "should allow it to destroy the job" do
        WorkerJob.class_eval do
          def handle_error(error)
            destroy
          end
        end

        WorkerJob.enqueue

        assert_equal 1, jobs_dataset.count
        run_jobs
        assert_equal 0, jobs_dataset.count

        assert_instance_of RuntimeError, notified_errors.first[:error]
        assert_equal "Error!", notified_errors.first[:error].message
      end

      it "should allow it to return false to skip the error notification" do
        WorkerJob.class_eval do
          def handle_error(error)
            retry_in_default_interval
            false
          end
        end

        assert_retry_cadence 4, 19, 84, 259
        assert_empty notified_errors
      end

      it "when the handle_error method is defined incorrectly" do
        WorkerJob.class_eval do
          def handle_error
          end
        end

        assert_retry_cadence 4, 19, 84, 259
        assert_equal 8, notified_errors.length
        assert_instance_of ArgumentError, notified_errors[0][:error]
        assert_match /wrong number of arguments/, notified_errors[0][:error].message

        assert_instance_of RuntimeError, notified_errors[1][:error]
        assert_equal "Error!", notified_errors[1][:error].message
      end

      it "when the handle_error method raises an error" do
        WorkerJob.class_eval do
          def handle_error(error)
            raise "handle_error error!"
          end
        end

        assert_retry_cadence 4, 19, 84, 259
        assert_equal 8, notified_errors.length
        assert_instance_of RuntimeError, notified_errors[0][:error]
        assert_equal "handle_error error!", notified_errors[0][:error].message

        assert_instance_of RuntimeError, notified_errors[1][:error]
        assert_equal "Error!", notified_errors[1][:error].message
      end

      it "should allow it to call super to get the default behavior" do
        WorkerJob.class_eval do
          def handle_error(error)
            super
          end
        end

        assert_retry_cadence 4, 19, 84, 259

        assert_instance_of RuntimeError, notified_errors.first[:error]
        assert_equal "Error!", notified_errors.first[:error].message
      end
    end
  end
end
