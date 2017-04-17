# frozen_string_literal: true

require 'spec_helper'

describe Que::Worker do
  before do
    @job_queue    = Que::JobQueue.new maximum_size: 20
    @result_queue = Que::ResultQueue.new

    @worker = Que::Worker.new job_queue:    @job_queue,
                              result_queue: @result_queue
  end

  def run_jobs(*jobs)
    @result_queue.clear
    jobs = jobs.flatten.map { |job| {priority: job[:priority], run_at: job[:run_at], id: job[:id]} }
    @job_queue.push *jobs
    sleep_until { @result_queue.to_a.sort == jobs.map{|j| j[:id]}.sort }
  end

  it "should repeatedly work jobs that are passed to it via its job_queue, ordered correctly" do
    begin
      $results = []

      class WorkerJob < Que::Job
        def run(number)
          $results << number
        end
      end

      [1, 2, 3].each { |i| WorkerJob.enqueue i, priority: i }
      job_ids = jobs.order_by(:priority).select_map(:id)
      run_jobs Que.execute("SELECT * FROM que_jobs").shuffle

      assert_equal [1, 2, 3], $results
      assert_equal job_ids, @result_queue.to_a

      events = logged_messages.select{|m| m['event'] == 'job_worked'}
      assert_equal 3, events.count
      assert_equal [1, 2, 3], events.map{|m| m['job']['priority']}
    ensure
      $results = nil
    end
  end

  it "should pass a job's arguments to the run method and mark it as processed" do
    ArgsJob.enqueue 1, 'two', {'three' => 3}
    assert_equal 1, jobs.count

    run_jobs Que.execute("SELECT * FROM que_jobs").first

    assert_equal 0, unprocessed_jobs.count
    assert_equal [1, 'two', {three: 3}], $passed_args
  end

  it "should work well with keyword arguments" do
    assert_nil $passed_args

    class KeywordArgsJob < Que::Job
      def run(keyword_arg_1:, keyword_arg_2: 'default')
        $passed_args = [keyword_arg_1, keyword_arg_2]
      end
    end

    KeywordArgsJob.enqueue(keyword_arg_1: 'passed', keyword_arg_2: 'passed_2')
    assert_equal 1, unprocessed_jobs.count
    assert_equal [{"keyword_arg_1" => 'passed', 'keyword_arg_2' => 'passed_2'}], JSON.parse(unprocessed_jobs.first[:args])
    run_jobs Que.execute(unprocessed_jobs.sql).first
    assert_equal 0, unprocessed_jobs.count
    assert_equal ['passed', 'passed_2'], $passed_args

    KeywordArgsJob.enqueue(keyword_arg_1: 'passed')
    assert_equal 1, unprocessed_jobs.count
    assert_equal [{"keyword_arg_1" => 'passed'}], JSON.parse(unprocessed_jobs.first[:args])
    run_jobs Que.execute(unprocessed_jobs.sql).first
    assert_equal 0, unprocessed_jobs.count
    assert_equal ['passed', 'default'], $passed_args
  end

  it "should make it easy to destroy the job within the same transaction as other changes" do
    class DestroyJob < Que::Job
      def run
        destroy
      end
    end

    DestroyJob.enqueue
    assert_equal 1, jobs.count

    run_jobs Que.execute("SELECT * FROM que_jobs").first
    assert_equal 0, jobs.count
  end

  it "should handle subclasses of other jobs" do
    begin
      class SubClassJob < Que::Job
        @priority = 2

        def run
          $job_spec_result << :sub
        end
      end

      class SubSubClassJob < SubClassJob
        @priority = 4

        def run
          super
          $job_spec_result << :subsub
        end
      end

      $job_spec_result = []
      SubClassJob.enqueue
      assert_equal [2], unprocessed_jobs.select_map(:priority)
      run_jobs Que.execute(unprocessed_jobs.sql).first
      assert_equal [:sub], $job_spec_result

      $job_spec_result = []
      SubSubClassJob.enqueue
      assert_equal [4], unprocessed_jobs.select_map(:priority)
      run_jobs Que.execute(unprocessed_jobs.sql).first
      assert_equal [:sub, :subsub], $job_spec_result
    ensure
      $job_spec_result = nil
    end
  end

  it "should handle namespaced subclasses" do
    begin
      $run = false

      module ModuleJobModule
        class ModuleJob < Que::Job
          def run
            $run = true
          end
        end
      end

      ModuleJobModule::ModuleJob.enqueue
      assert_equal "ModuleJobModule::ModuleJob", jobs.get(:job_class)

      run_jobs Que.execute("SELECT * FROM que_jobs").first
      assert_equal true, $run
    ensure
      $run = nil
    end
  end

  it "should make a job's argument hashes indifferently accessible" do
    assert_equal 0, jobs.count
    ArgsJob.enqueue 1, 'two', {'array' => [{'number' => 3}]}
    assert_equal 1, jobs.count

    run_jobs Que.execute("SELECT * FROM que_jobs").first
    assert_equal 3, $passed_args.last[:array].first[:number]
  end

  it "should skip a job without incident if passed the pk for a job that doesn't exist" do
    assert_equal 0, jobs.count
    run_jobs priority: 1,
             run_at:   Time.now,
             id:       587648

    assert_equal [587648], @result_queue.to_a
  end

  it "should only take jobs that meet its priority requirement" do
    @worker.priority = 10

    jobs = (1..20).map { |i| {priority: i, run_at: Time.now, id: i} }

    @job_queue.push *jobs

    sleep_until { @result_queue.to_a == (1..10).to_a }

    assert_equal jobs[10..19], @job_queue.to_a
  end

  describe "when an error is raised" do
    it "should not crash the worker" do
      ErrorJob.enqueue priority: 1
      Que::Job.enqueue priority: 2

      job_ids = jobs.order_by(:priority).select_map(:id)
      run_jobs Que.execute("SELECT * FROM que_jobs")
      assert_equal job_ids, @result_queue.to_a

      events = logged_messages.select{|m| m['event'] == 'job_errored'}
      assert_equal 1, events.count

      event = events.first
      assert_equal 1, event['job']['priority']
      assert_kind_of Integer, event['job']['id']
      assert_equal "ErrorJob!", event['error']
    end

    it "should pass it to the error notifier" do
      begin
        error = nil
        Que.error_notifier = proc { |e| error = e }

        ErrorJob.enqueue priority: 1

        run_jobs Que.execute("SELECT * FROM que_jobs")

        assert_instance_of RuntimeError, error
        assert_equal "ErrorJob!", error.message
      ensure
        Que.error_notifier = nil
      end
    end

    it "should exponentially back off the job" do
      ErrorJob.enqueue

      run_jobs Que.execute("SELECT * FROM que_jobs")

      assert_equal 1, jobs.count
      job = jobs.first
      assert_equal 1, job[:error_count]
      assert_equal "ErrorJob!", job[:last_error]
      assert_in_delta job[:run_at], Time.now + 4, 3

      jobs.update error_count: 5,
                  run_at:      Time.now - 60

      run_jobs Que.execute("SELECT * FROM que_jobs")

      assert_equal 1, jobs.count
      job = jobs.first
      assert_equal 6, job[:error_count]
      assert_equal "ErrorJob!", job[:last_error]
      assert_in_delta job[:run_at], Time.now + 1299, 3
    end

    it "should respect a custom retry interval" do
      class RetryIntervalJob < ErrorJob
        @retry_interval = 5
      end

      RetryIntervalJob.enqueue

      run_jobs Que.execute("SELECT * FROM que_jobs")

      assert_equal 1, jobs.count
      job = jobs.first

      assert_equal 1, job[:error_count]
      assert_equal "ErrorJob!", job[:last_error]
      assert_in_delta job[:run_at], Time.now + 5, 3

      jobs.update error_count: 5,
                  run_at:      Time.now - 60

      run_jobs Que.execute("SELECT * FROM que_jobs")

      assert_equal 1, jobs.count
      job = jobs.first

      assert_equal 6, job[:error_count]
      assert_equal "ErrorJob!", job[:last_error]
      assert_in_delta job[:run_at], Time.now + 5, 3
    end

    it "should respect a custom retry interval formula" do
      class RetryIntervalFormulaJob < ErrorJob
        @retry_interval = proc { |count| count * 10 }
      end

      RetryIntervalFormulaJob.enqueue

      run_jobs Que.execute("SELECT * FROM que_jobs")

      assert_equal 1, jobs.count
      job = jobs.first
      assert_equal 1, job[:error_count]
      assert_equal "ErrorJob!", job[:last_error]
      assert_in_delta job[:run_at], Time.now + 10, 3

      jobs.update error_count: 5,
                  run_at:      Time.now - 60

      run_jobs Que.execute("SELECT * FROM que_jobs")

      assert_equal 1, jobs.count
      job = jobs.first
      assert_equal 6, job[:error_count]
      assert_equal "ErrorJob!", job[:last_error]
      assert_in_delta job[:run_at], Time.now + 60, 3
    end

    it "should throw an error properly if there's no corresponding job class" do
      jobs.insert job_class: "NonexistentClass"

      run_jobs Que.execute("SELECT * FROM que_jobs")

      assert_equal 1, jobs.count
      job = jobs.first
      assert_equal 1, job[:error_count]
      assert_match /uninitialized constant:? .*NonexistentClass/, job[:last_error]
      assert_in_delta job[:run_at], Time.now + 4, 3
    end

    it "should throw an error properly if the corresponding job class doesn't descend from Que::Job" do
      class J
        def run(*args)
        end
      end

      Que.enqueue job_class: "J"

      run_jobs Que.execute("SELECT * FROM que_jobs")

      assert_equal 1, jobs.count
      job = jobs.first
      assert_equal 1, job[:error_count]
      assert_in_delta job[:run_at], Time.now + 4, 3
    end

    describe "in a job class that has a custom error handler" do
      it "should allow it to schedule a retry after a specific interval" do
        begin
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

          run_jobs Que.execute("SELECT * FROM que_jobs")

          assert_equal 1, jobs.count
          job = jobs.first
          assert_equal 1, job[:error_count]
          assert_match /\ABlah!/, job[:last_error]
          assert_in_delta job[:run_at], Time.now + 42, 3
        ensure
          Que.error_notifier = nil
        end
      end

      it "should allow it to destroy the job" do
        begin
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

          assert_equal 1, jobs.count
          run_jobs Que.execute("SELECT * FROM que_jobs")
          assert_equal 0, jobs.count
        ensure
          Que.error_notifier = nil
        end
      end

      it "should allow it to return false to skip the error notification" do
        begin
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

          assert_equal 1, unprocessed_jobs.count
          run_jobs Que.execute("SELECT * FROM que_jobs")
          assert_equal 0, unprocessed_jobs.count

          assert_nil error
        ensure
          Que.error_notifier = nil
        end
      end

      it "should allow it to call super to get the default behavior" do
        begin
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
          run_jobs Que.execute("SELECT * FROM que_jobs")
          assert_nil $error_handler_failed

          assert_equal 1, jobs.count
          job = jobs.first
          assert_equal 1, job[:error_count]
          assert_match /\ABlah!/, job[:last_error]
          assert_in_delta job[:run_at], Time.now + 4, 3
        ensure
          Que.error_notifier = nil
        end
      end
    end
  end
end
