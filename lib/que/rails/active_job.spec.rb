# frozen_string_literal: true

require 'spec_helper'

if defined?(::ActiveJob)
  describe "running jobs via ActiveJob" do
    before do
      class TestJobClass < ActiveJob::Base
        def run(*args)
          $args = args
        end

        # ActiveJob uses #perform but we use #run - to make sure that all the
        # spec cases that redefine #run still work, just make it an alias.
        def perform(*args)
          run(*args)
        end
      end
    end

    after do
      Object.send :remove_const, :TestJobClass
      $args = nil
    end

    def execute_raw(*args)
      TestJobClass.perform_later(*args)
    end

    def execute(*args)
      worker # Make sure worker is initialized.

      wrapper = execute_raw(*args)

      assert_equal 1, jobs_dataset.count

      attrs = jobs_dataset.first!

      job_queue.push(Que::Metajob.new(attrs))

      sleep_until! { results(message_type: :job_finished).map{|m| m.fetch(:metajob).id} == [attrs[:id]] }
      attrs
    end

    it "should pass its arguments to the run method" do
      execute(1, 2)
      assert_equal [1, 2], $args
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
      assert_equal [5, 6], $args

      assert_instance_of ActiveJob::QueueAdapters::QueAdapter::JobWrapper, passed_1
      assert_equal([5, 6], passed_1.que_attrs[:data][:args].first[:arguments])

      assert_equal passed_1.object_id, passed_2.object_id
    end

    it "raising an unrecoverable error shouldn't finish the job record" do
      CustomExceptionSubclass = Class.new(Exception)

      TestJobClass.class_eval do
        def run(*args)
          raise CustomExceptionSubclass
        end
      end

      assert_raises(CustomExceptionSubclass) { execute(5, 6) }

      assert_equal 1, active_jobs_dataset.count
      assert_equal [5, 6], active_jobs_dataset.get(:data)[:args].first[:arguments]
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
            def run(*args)
              $args = args
            end
          end

          execute_raw(3, 4)
          assert_equal [3, 4], $args

          Que.execute "ROLLBACK"
        end
      end

      it "should propagate errors raised during the job" do
        TestJobClass.class_eval do
          def run(*args)
            raise "Oopsie!"
          end
        end

        error = assert_raises(RuntimeError) { execute_raw(3, 4) }
        assert_equal "Oopsie!", error.message
      end
    end
  end
end
