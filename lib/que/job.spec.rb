# frozen_string_literal: true

require 'spec_helper'

describe Que::Job do
  let(:notified_errors) { [] }

  before do
    Que.error_notifier = proc { |e| notified_errors << e }

    class TestJobClass < Que::Job
      def run(*args, **kwargs)
        $args = args
        $kwargs = kwargs
      end
    end
  end

  after do
    Object.send :remove_const, :TestJobClass
    $args = nil
    $kwargs = nil
  end

  module ActsLikeAJob
    def self.included(base)
      base.class_eval do
        def expected_job_count
          should_persist_job ? 1 : 0
        end

        it "should pass its arguments to the run method" do
          execute(1, 2)
          assert_equal([1, 2], $args)
        end

        it "should pass its keyword arguments to the run method" do
          execute(a: 1, b: 2)
          assert_equal({ a: 1, b: 2 }, $kwargs)
        end

        it "should deep-freeze its arguments" do
          execute([], {}, 'blah'.dup)

          assert_equal([[], {}, 'blah'.dup], $args)

          array = $args
          assert array[0].frozen?
          assert array[1].frozen?
          assert array[2].frozen?
        end

        it "should deep-freeze its keyword arguments" do
          execute(array: [], hash: {}, string: 'blah'.dup)

          assert_equal({array: [], hash: {}, string: 'blah'.dup}, $kwargs)

          hash = $kwargs
          assert hash[:array].frozen?
          assert hash[:hash].frozen?
          assert hash[:string].frozen?
        end

        it "treats the last hash literal as a positional argument" do
          execute({a: 1, b: 2})
          assert_equal([{a: 1, b: 2}], $args)
        end

        it "should symbolize hash argument keys" do
          execute({a: 1, b: 2}, c: 3, d: 4)
          assert_equal([{a: 1, b: 2}], $args)
        end

        it "should symbolize hash argument keys even if they were originally passed as strings" do
          # The run() helper should convert these to symbols, just as if they'd
          # been passed through the DB.
          execute({'a' => 1, 'b' => 2}, c: 3, d: 4)
          assert_equal([{a: 1, b: 2}], $args)
        end

        it "should symbolize keyword argument keys" do
          execute(a: 1, b: 2)
          assert_equal({a: 1, b: 2}, $kwargs)
        end

        it "should symbolize keyword argument keys even if they were originally passed as strings" do
          # The run() helper should convert these to symbols, just as if they'd
          # been passed through the DB.
          execute('a' => 1, 'b' => 2)
          assert_equal({a: 1, b: 2}, $kwargs)
        end

        it "should handle keyword arguments just fine" do
          TestJobClass.class_eval do
            def run(a:, b: 4, c: 3)
              $kwargs = [a, b, c]
            end
          end

          execute(a: 1, b: 2)
          assert_equal [1, 2, 3], $kwargs
        end

        it "should handle keyword arguments even if they were originally passed as strings" do
          TestJobClass.class_eval do
            def run(a:, b: 4, c: 3)
              $args = [a, b, c]
            end
          end

          # The run() helper should convert these to symbols, just as if they'd
          # been passed through the DB.
          execute('a' => 1, 'b' => 2)
          assert_equal [1, 2, 3], $args
        end

        it "should expose the job's error_count" do
          TestJobClass.class_eval do
            def run
              $error_count = error_count
            end
          end

          execute
          assert_equal 0, $error_count
        end

        it "should make it easy to destroy the job" do
          TestJobClass.class_eval do
            def run
              destroy
            end
          end

          execute
          assert_empty jobs_dataset
        end

        it "should make it easy to finish the job" do
          TestJobClass.class_eval do
            def run
              finish
            end
          end

          execute

          if should_persist_job
            assert_empty active_jobs_dataset
            refute_empty finished_jobs_dataset
          else
            assert_empty jobs_dataset
          end
        end

        it "should make it easy to expire the job" do
          TestJobClass.class_eval do
            def run
              expire
            end
          end

          execute

          if should_persist_job
            assert_empty active_jobs_dataset
            refute_empty expired_jobs_dataset
          else
            assert_empty jobs_dataset
          end
        end

        it "should make it easy to override the default resolution action" do
          TestJobClass.class_eval do
            def run
            end

            def default_resolve_action
              finish
            end
          end

          execute

          if should_persist_job
            assert_empty active_jobs_dataset
            refute_empty finished_jobs_dataset
          else
            assert_empty jobs_dataset
          end
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

          execute(5, 6)

          if defined?(ApplicationJob)
            assert_instance_of ActiveJob::QueueAdapters::QueAdapter::JobWrapper, passed_1
            assert_equal([5, 6], passed_1.que_attrs[:args].first[:arguments])
          else
            assert_instance_of TestJobClass, passed_1
            assert_equal([5, 6], passed_1.que_attrs[:args])
          end

          assert_equal passed_1.object_id, passed_2.object_id
        end

        it "calling retry_in when there's no error shouldn't be problematic" do
          TestJobClass.class_eval do
            def run
              retry_in(50)
            end
          end

          job = execute

          assert_equal expected_job_count, active_jobs_dataset.count

          if should_persist_job
            assert_in_delta active_jobs_dataset.get(:run_at), Time.now + 50, QueSpec::TIME_SKEW
            assert_equal [job.que_attrs[:id]], active_jobs_dataset.select_map(:id)
          end
        end

        it "raising an unrecoverable error shouldn't delete the job record" do
          if Thread.current.respond_to?(:report_on_exception=)
            worker.thread.report_on_exception = false
          end

          error_class = Class.new(Exception)

          TestJobClass.class_eval do
            define_method :run do
              raise error_class
            end
          end

          assert_empty jobs_dataset
          assert_raises(error_class) { execute }
          assert_equal expected_job_count, jobs_dataset.count
        end

        describe "#handle_error" do
          before do
            TestJobClass.class_eval do
              def run
                raise "Uh-oh!"
              end
            end
          end

          it "should be passed the error object and expose the correct error_count" do
            TestJobClass.class_eval do
              def handle_error(error)
                $args = [error_count, error]
              end
            end

            error = assert_raises(RuntimeError) { execute }
            assert_equal "Uh-oh!", error.message

            count, error_2 = $args
            assert_equal 1, count

            assert_equal 1, notified_errors.count
            assert_equal error_2, notified_errors.first
          end

          it "should make it easy to signal that the error should be notified" do
            TestJobClass.class_eval do
              def handle_error(error)
                true # Notify error
              end
            end

            error = assert_raises(RuntimeError) { execute }

            assert_equal "Uh-oh!", error.message
            assert_equal "Uh-oh!", notified_errors.first.message
          end

          it "should make it easy to signal that the error should not be notified" do
            TestJobClass.class_eval do
              def handle_error(error)
                false # Do not notify error
              end
            end

            assert_raises(RuntimeError) { execute }

            assert_empty notified_errors
          end

          it "when it raises an error of its own should notify it as well" do
            TestJobClass.class_eval do
              def handle_error(error)
                raise "Uh-oh again!"
              end
            end

            error = assert_raises(RuntimeError) { execute }
            assert_equal "Uh-oh!", error.message

            assert_equal expected_job_count, jobs_dataset.count
            assert_equal ["Uh-oh again!", "Uh-oh!"], notified_errors.map(&:message)
          end

          if defined?(ActiveJob) # GlobalID isn't a thing unless we have ActiveJob.
            it "should support the use of GlobalId arguments" do
              skip "Not yet implemented"

              Que::Job.enqueue # Test job object

              job = QueJob.first
              job.update(finished_at: Time.now)
              gid = job.to_global_id(app: :test)

              execute(job_object: gid.to_s)

              assert_equal(
                [{job_object: job}],
                $args,
              )
            end
          end
        end
      end
    end
  end

  module ActsLikeASynchronousJob
    def self.included(base)
      base.class_eval do
        it "shouldn't fail if there's no DB connection" do
          # We want to make sure that the act of working a job synchronously
          # doesn't necessarily touch the DB. One way to do this is to run the
          # job inside a failed transaction.
          Que.checkout do
            Que.execute "BEGIN"
            assert_raises(PG::SyntaxError) { Que.execute "This isn't valid SQL!" }
            assert_raises(PG::InFailedSqlTransaction) { Que.execute "SELECT 1" }

            TestJobClass.class_eval do
              def run(*args)
                $args = args
                destroy
              end
            end

            execute(3, 4)
            assert_equal [3, 4], $args

            Que.execute "ROLLBACK"
          end
        end
      end
    end
  end

  describe "the JobClass.run() method" do
    include ActsLikeAJob
    include ActsLikeASynchronousJob

    let(:should_persist_job) { false }

    def execute(*args)
      TestJobClass.run(*args)
    end
    ruby2_keywords(:execute) if respond_to?(:ruby2_keywords, true)
  end

  describe "the JobClass.enqueue() method when run_synchronously is set" do
    include ActsLikeAJob
    include ActsLikeASynchronousJob

    let(:should_persist_job) { false }

    def execute(*args)
      TestJobClass.run_synchronously = true
      TestJobClass.enqueue(*args)
    end
    ruby2_keywords(:execute) if respond_to?(:ruby2_keywords, true)
  end

  describe "running jobs from the DB" do
    include ActsLikeAJob

    let(:should_persist_job) { true }

    def execute(*args)
      worker # Make sure worker is initialized.

      job = TestJobClass.enqueue(*args)
      attrs = job.que_attrs

      job_buffer.push(Que::Metajob.new(attrs))

      sleep_until_equal([attrs[:id]]) { results(message_type: :job_finished).map{|m| m.fetch(:metajob).id} }

      if m = jobs_dataset.where(id: job.que_attrs[:id]).get(:last_error_message)
        klass, message = m.split(": ", 2)
        raise Que.constantize(klass), message
      end

      job
    end
    ruby2_keywords(:execute) if respond_to?(:ruby2_keywords, true)

    it "should handle subclassed jobs" do
      Object.send :remove_const, :TestJobClass

      superclass = Class.new(Que::Job) do
        def run
          $args << 2
        end
      end

      Object.const_set(:TestJobClass, Class.new(superclass) {
        def run
          $args << 1
          super
          $args << 3
        end
      })

      $args = []
      execute

      assert_equal [1, 2, 3], $args
    end
  end

  if defined?(::ActiveJob)
    describe "running jobs through ActiveJob when a subclass has our helpers included" do
      include ActsLikeAJob

      let(:should_persist_job) { true }

      before do
        Object.send :remove_const, :TestJobClass

        class ApplicationJob < ActiveJob::Base
          include Que::ActiveJob::JobExtensions
        end

        class TestJobClass < ApplicationJob
          def run(*args, **kwargs)
            $args = args
            $kwargs = kwargs
          end
        end
      end

      after do
        Object.send :remove_const, :ApplicationJob
      end

      def execute(*args)
        worker # Make sure worker is initialized.

        TestJobClass.perform_later(*args)

        assert_equal 1, jobs_dataset.count
        attrs = jobs_dataset.first!

        job_buffer.push(Que::Metajob.new(attrs))

        sleep_until_equal([attrs[:id]]) { results(message_type: :job_finished).map{|m| m.fetch(:metajob).id} }

        if m = jobs_dataset.where(id: attrs[:id]).get(:last_error_message)
          klass, message = m.split(": ", 2)
          raise Que.constantize(klass), message
        end

        ActiveJob::QueueAdapters::QueAdapter::JobWrapper.new(attrs)
      end
      ruby2_keywords(:execute) if respond_to?(:ruby2_keywords, true)

      it "should still support using the perform method" do
        TestJobClass.send :undef_method, :run

        TestJobClass.class_eval do
          def perform(*args)
            $args = args
            destroy
          end
        end

        execute("arg1" => 1, "arg2" => 2)
        assert_equal([{'arg1' => 1, 'arg2' => 2}], $args)
      end

      it "when there is no run method shouldn't cause a problem" do
        Object.send :remove_const, :TestJobClass

        class TestJobClass < ApplicationJob; end

        error = assert_raises(Que::Error) { execute(1, 2) }
        assert_equal "Job class TestJobClass didn't define a run() method!", error.message
        assert_equal expected_job_count, jobs_dataset.count
      end
    end
  end
end
