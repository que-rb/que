# frozen_string_literal: true

require 'spec_helper'

if defined?(::ActiveJob)
  describe "enqueueing/running jobs via ActiveJob" do
    before do
      class TestJobClass < ActiveJob::Base
        def perform(*args, **kwargs)
          $args = args
          $kwargs = kwargs
        end
      end
      class OtherTestJobClass < ActiveJob::Base; end
    end

    after do
      Object.send :remove_const, :TestJobClass
      $args = nil
      $kwargs = nil
      Object.send :remove_const, :OtherTestJobClass
    end

    def execute(&perform_later_block)
      worker # Make sure worker is initialized.
      perform_later_block.call

      assert_equal 1, active_jobs_dataset.count
      attrs = active_jobs_dataset.first!

      job_buffer.push(Que::Metajob.new(attrs))

      sleep_until_equal([attrs[:id]]) { results(message_type: :job_finished).map{|m| m.fetch(:metajob).id} }
      attrs
    end

    it "should pass its arguments to the run method" do
      execute { TestJobClass.perform_later(1, 2) }
      assert_equal [1, 2], $args
    end

    it "should handle argument types appropriately" do
      execute { TestJobClass.perform_later(symbol_arg: 1, "string_arg" => 2) }
      assert_equal(
        {symbol_arg: 1, "string_arg" => 2},
        $kwargs,
      )
    end

    it 'configures jobs with supported job options' do
      run_at = Time.now.round + 60
      attrs = execute do
        TestJobClass.new.enqueue(
          queue: 'test_queue',
          priority: 10,
          wait_until: run_at,
        )
      end
      assert_equal(
        {
          queue: 'test_queue',
          priority: 10,
          run_at: run_at,
        },
        attrs.slice(:queue, :priority, :run_at),
      )
    end

    it "shouldn't disrupt the use of GlobalId arguments" do
      skip "GlobalID not found!" unless defined?(::GlobalID)

      Que::Job.enqueue # Test job object

      job = QueJob.first
      job.update(finished_at: Time.now)

      execute { TestJobClass.perform_later(job_object: job) }

      assert_equal(
        {job_object: job},
        $kwargs,
      )
    end

    it "should wrap the run method in whatever job_middleware are defined" do
      passed_1 = passed_2 = nil

      Que.job_middleware.push(
        -> (job, &block) {
          passed_1 = job
          block.call
          nil # Shouldn't matter what's returned.
        }
      )

      Que.job_middleware.push(
        -> (job, &block) {
          passed_2 = job
          block.call
          nil # Shouldn't matter what's returned.
        }
      )

      execute { TestJobClass.perform_later(5, 6) }
      assert_equal [5, 6], $args

      assert_instance_of ActiveJob::QueueAdapters::QueAdapter::JobWrapper, passed_1
      assert_equal([5, 6], passed_1.que_attrs[:args].first[:arguments])

      assert_equal passed_1.object_id, passed_2.object_id
    end

    it "raising an unrecoverable error shouldn't finish the job record" do
      if Thread.current.respond_to?(:report_on_exception=)
        worker.thread.report_on_exception = false
      end

      CustomExceptionSubclass = Class.new(Exception)

      TestJobClass.class_eval do
        def perform(*args)
          raise CustomExceptionSubclass
        end
      end

      assert_raises(CustomExceptionSubclass) do
        execute { TestJobClass.perform_later(5, 6) }
      end

      assert_equal 1, active_jobs_dataset.count
      assert_equal [5, 6], active_jobs_dataset.get(:args).first[:arguments]
    end

    describe "when running synchronously" do
      before do
        Que.run_synchronously = true
      end

      it "shouldn't fail if there's no DB connection" do
        Que.checkout do
          Que.execute "BEGIN"
          assert_raises(PG::SyntaxError) { Que.execute "This isn't valid SQL!" }
          assert_raises(PG::InFailedSqlTransaction) { Que.execute "SELECT 1" }

          TestJobClass.class_eval do
            def perform(*args)
              $args = args
            end
          end

          TestJobClass.perform_later(3, 4)
          assert_equal [3, 4], $args

          assert_raises(PG::InFailedSqlTransaction) { Que.execute "SELECT 1" }

          Que.execute "ROLLBACK"
        end
      end

      it "should propagate errors raised during the job" do
        notified_error = nil
        Que.error_notifier = proc { |e| notified_error = e }

        TestJobClass.class_eval do
          def perform(*args)
            raise "Oopsie!"
          end
        end

        error = assert_raises(RuntimeError) do
          TestJobClass.perform_later(3, 4)
        end
        assert_equal "Oopsie!", error.message
        assert_equal error, notified_error
      end
    end

    def assert_enqueue_active_job(
      expected_queues:,
      expected_priorities:,
      expected_run_ats:,
      expected_active_job_classes:,
      expected_active_job_arguments:,
      expected_count:,
      assert_results:,
      &enqueue_block
    )

      assert_equal 0, jobs_dataset.count

      results = enqueue_block.call

      assert_equal expected_count, jobs_dataset.count

      if assert_results
        results.each_with_index do |result, i|
          assert_kind_of Que::Job, result
          assert_instance_of ActiveJob::QueueAdapters::QueAdapter::JobWrapper, result

          assert_equal expected_priorities[i], result.que_attrs[:priority]
          assert_equal expected_active_job_classes[i], result.que_attrs[:args].first[:job_class]
          assert_equal expected_active_job_arguments[i], result.que_attrs[:args].first[:arguments]
          assert_equal ({}), result.que_attrs[:kwargs]
          assert_equal ({}), result.que_attrs[:data]
        end
      end

      jobs_dataset.order(:id).each_with_index do |job, i|
        assert_equal expected_queues[i], job[:queue]
        assert_equal expected_priorities[i], job[:priority]
        assert_equal expected_active_job_classes[i], job[:args].first[:job_class]
        assert_equal expected_active_job_arguments[i], job[:args].first[:arguments]
        assert_in_delta job[:run_at], expected_run_ats[i], QueSpec::TIME_SKEW
        assert_equal 'ActiveJob::QueueAdapters::QueAdapter::JobWrapper', job[:job_class]
        assert_equal ({}), job[:kwargs]
        assert_equal ({}), job[:data]
      end

      jobs_dataset.delete
    end

    describe "with Que.bulk_enqueue" do
      it "should be able to queue multiple jobs with different classes and job options" do
        assert_enqueue_active_job(
          expected_count: 2,
          expected_queues: ['default', 'custom'],
          expected_priorities: [100, 200],
          expected_run_ats: [Time.now, Time.now + 60],
          expected_active_job_classes: ['TestJobClass', 'OtherTestJobClass'],
          expected_active_job_arguments: [[1, 2], [3, 4]],
          assert_results: true,
        ) do
          Que.bulk_enqueue do
            TestJobClass.perform_later(1, 2)
            OtherTestJobClass.set(wait: 1.minute, queue: 'custom', priority: 200).perform_later(3, 4)
          end
        end
      end
    end

    if ActiveJob.gem_version >= Gem::Version.new('7.1')
      describe "with ActiveJob.perform_all_later" do
        it "should be able to queue multiple jobs with different classes and job options" do
          assert_enqueue_active_job(
            expected_count: 2,
            expected_queues: ['default', 'custom'],
            expected_priorities: [100, 200],
            expected_run_ats: [Time.now, Time.now + 60],
            expected_active_job_classes: ['TestJobClass', 'OtherTestJobClass'],
            expected_active_job_arguments: [[1, 2], [3, 4]],
            assert_results: false,
          ) do
            ActiveJob.perform_all_later([
              TestJobClass.new(1, 2),
              OtherTestJobClass.new(3, 4).set(wait: 1.minute, queue: 'custom', priority: 200),
            ])
          end
        end

        it "should set provider_job_id on job instances" do
          jobs = [TestJobClass.new, TestJobClass.new]
          ActiveJob.perform_all_later(jobs)
          que_jobs = jobs_dataset.order(:id).to_a

          assert_equal jobs[0].provider_job_id, que_jobs[0][:id]
          assert_equal jobs[1].provider_job_id, que_jobs[1][:id]
        end
      end
    end
  end
end
