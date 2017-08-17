# frozen_string_literal: true

require 'spec_helper'

describe Que::Job do
  before do
    class TestJobClass < Que::Job
      def run(*args)
        $args = args
      end
    end
  end

  after do
    Object.send :remove_const, :TestJobClass
    $args = nil
  end

  module ActsLikeAJob
    def self.included(base)
      base.class_eval do
        it "should pass its arguments to the run method" do
          execute(1, 2)
          assert_equal [1, 2], $args
        end

        it "should deep-freeze its arguments" do
          execute(array: [], hash: {}, string: 'blah'.dup)

          assert_equal([{array: [], hash: {}, string: 'blah'.dup}], $args)

          hash = $args.first
          assert hash.frozen?
          assert hash[:array].frozen?
          assert hash[:hash].frozen?
          assert hash[:string].frozen?
        end

        it "should handle keyword arguments just fine" do
          TestJobClass.class_eval do
            def run(a:, b: 4, c: 3)
              $args = [a, b, c]
            end
          end

          execute(a: 1, b: 2)
          assert_equal [1, 2, 3], $args

          # The run() helper should convert these to symbols, just as if they'd
          # been passed through the DB.
          execute('a' => 1, 'b' => 2)
          assert_equal [1, 2, 3], $args
        end

        it "should symbolize argument hashes" do
          execute(a: 1, b: 2)
          assert_equal([{a: 1, b: 2}], $args)

          # The run() helper should convert these to symbols, just as if they'd
          # been passed through the DB.
          execute('a' => 1, 'b' => 2)
          assert_equal([{a: 1, b: 2}], $args)
        end

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
          assert_empty active_jobs_dataset
        end

        it "should make it easy to override the default finishing action" do
          TestJobClass.class_eval do
            def run
            end

            def default_finish_action
              destroy
            end
          end

          execute
          assert_empty jobs_dataset
        end

        it "should wrap the run method in whatever middleware are defined" do
          passed_1 = passed_2 = nil

          Que.middleware.push(
            -> (job, &block) {
              passed_1 = job
              block.call
              nil # Shouldn't matter what's returned.
            }
          )

          Que.middleware.push(
            -> (job, &block) {
              passed_2 = job
              block.call
              nil # Shouldn't matter what's returned.
            }
          )

          execute(5, 6)

          assert_instance_of TestJobClass, passed_1
          assert_equal({args: [5, 6]}, passed_1.que_attrs[:data])

          assert_equal passed_1.object_id, passed_2.object_id
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

        it "should propagate errors raised during the job, and not invoke handle_error" do
          TestJobClass.class_eval do
            def run
              raise "Uh-oh!"
            end

            def handle_error
              $args = true
            end
          end

          error = assert_raises { execute }
          assert_equal "Uh-oh!", error.message
          assert_nil $args
        end
      end
    end
  end

  describe "the JobClass.run() method" do
    include ActsLikeAJob
    include ActsLikeASynchronousJob

    def execute(*args)
      TestJobClass.run(*args)
    end
  end

  describe "the JobClass.enqueue() method when run_synchronously is set" do
    include ActsLikeAJob
    include ActsLikeASynchronousJob

    def execute(*args)
      TestJobClass.run_synchronously = true
      TestJobClass.enqueue(*args)
    end
  end

  describe "running jobs from the DB" do
    include ActsLikeAJob

    let :job_queue do
      Que::JobQueue.new(maximum_size: 20)
    end

    let :result_queue do
      Que::ResultQueue.new
    end

    let :worker do
      Que::Worker.new \
        job_queue:    job_queue,
        result_queue: result_queue
    end

    def execute(*args)
      worker # Make sure worker is initialized.

      job = TestJobClass.enqueue(*args)
      attrs = job.que_attrs

      job_queue.push(
        queue:    attrs[:queue],
        priority: attrs[:priority],
        run_at:   attrs[:run_at],
        id:       attrs[:id],
      )

      sleep_until! { result_queue.clear.map{|m| m.fetch(:id)} == [attrs[:id]] }
      job
    end

    it "should make it easy to override the finishing action" do
      TestJobClass.class_eval do
        def finish
          $args = []
          $args << :before_destroy
          destroy
          $args << :after_destroy
        end
      end

      execute
      assert_equal [:before_destroy, :after_destroy], $args
      assert_empty jobs_dataset
    end

    it "calling retry_in when there's no error shouldn't be problematic"

    it "raising an unrecoverable error shouldn't delete the job record" do
      class BigBadError < Exception; end

      TestJobClass.class_eval do
        def run
          raise BigBadError
        end
      end

      assert_empty jobs_dataset
      assert_raises(BigBadError) { execute }
      refute_empty jobs_dataset
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
        error = nil
        Que.error_notifier = proc { |e| error = e }

        TestJobClass.class_eval do
          def handle_error(error)
            $args = [error_count, error]
          end
        end

        execute

        assert_equal "Uh-oh!", error.message

        count, error_2 = $args
        assert_equal 1, count
        assert_equal error, error_2
      end

      it "should make it easy to signal that the error should be notified" do
        error = nil
        Que.error_notifier = proc { |e| error = e }

        TestJobClass.class_eval do
          def handle_error(error)
            true # Notify error
          end
        end

        execute
        assert_equal "Uh-oh!", error.message
      end

      it "should make it easy to signal that the error should not be notified" do
        error = nil
        Que.error_notifier = proc { |e| error = e }

        TestJobClass.class_eval do
          def handle_error(error)
            false # Do not notify error
          end
        end

        execute
        assert_nil error
      end

      it "when it raises an error of its own should notify it as well" do
        errors = []
        Que.error_notifier = proc { |e| errors << e }

        TestJobClass.class_eval do
          def handle_error(error)
            raise "Uh-oh again!"
          end
        end

        execute

        assert_equal 1, jobs_dataset.count

        assert_equal ["Uh-oh again!", "Uh-oh!"], errors.map(&:message)
      end
    end
  end
end
