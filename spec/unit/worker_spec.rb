# frozen_string_literal: true

require 'spec_helper'

describe Que::Worker do
  before do
    @job_queue    = Que::JobQueue.new maximum_size: 20
    @result_queue = Que::JobQueue.new

    @worker = Que::Worker.new job_queue:    @job_queue,
                              result_queue: @result_queue
  end

  def run_jobs(*jobs)
    @result_queue.clear
    jobs = jobs.flatten.map { |job| job.values_at(:priority, :run_at, :job_id) }
    @job_queue.push *jobs
    sleep_until(3600) { @result_queue.to_a.sort == jobs.sort }
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
      job_ids = DB[:que_jobs].order_by(:priority).select_map(:job_id)
      run_jobs Que.execute("SELECT * FROM que_jobs").shuffle

      $results.should == [1, 2, 3]
      @result_queue.to_a.map{|pk| pk[-1]}.should == job_ids

      events = logged_messages.select{|m| m['event'] == 'job_worked'}
      events.count.should be 3
      events.map{|m| m['job']['priority']}.should == [1, 2, 3]
    ensure
      $results = nil
    end
  end

  it "should pass a job's arguments to the run method and delete it from the database" do
    ArgsJob.enqueue 1, 'two', {'three' => 3}
    DB[:que_jobs].count.should be 1

    run_jobs Que.execute("SELECT * FROM que_jobs").first

    DB[:que_jobs].count.should be 0
    $passed_args.should == [1, 'two', {three: 3}]
  end

  it "should work well with keyword arguments" do
    $passed_args.should == nil

    class KeywordArgsJob < Que::Job
      def run(keyword_arg_1:, keyword_arg_2: 'default')
        $passed_args = [keyword_arg_1, keyword_arg_2]
      end
    end

    KeywordArgsJob.enqueue(keyword_arg_1: 'passed', keyword_arg_2: 'passed_2')
    DB[:que_jobs].count.should be 1
    JSON.parse(DB[:que_jobs].first[:args]).should == [{"keyword_arg_1" => 'passed', 'keyword_arg_2' => 'passed_2'}]
    run_jobs Que.execute("SELECT * FROM que_jobs").first
    DB[:que_jobs].count.should be 0
    $passed_args.should == ['passed', 'passed_2']

    KeywordArgsJob.enqueue(keyword_arg_1: 'passed')
    DB[:que_jobs].count.should be 1
    JSON.parse(DB[:que_jobs].first[:args]).should == [{"keyword_arg_1" => 'passed'}]
    run_jobs Que.execute("SELECT * FROM que_jobs").first
    DB[:que_jobs].count.should be 0
    $passed_args.should == ['passed', 'default']
  end

  it "should make it easy to destroy the job within the same transaction as other changes" do
    class DestroyJob < Que::Job
      def run
        destroy
      end
    end

    DestroyJob.enqueue
    DB[:que_jobs].count.should be 1

    run_jobs Que.execute("SELECT * FROM que_jobs").first
    DB[:que_jobs].count.should be 0
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
      DB[:que_jobs].select_map(:priority).should == [2]
      run_jobs Que.execute("SELECT * FROM que_jobs").first
      $job_spec_result.should == [:sub]

      $job_spec_result = []
      SubSubClassJob.enqueue
      DB[:que_jobs].select_map(:priority).should == [4]
      run_jobs Que.execute("SELECT * FROM que_jobs").first
      $job_spec_result.should == [:sub, :subsub]
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
      DB[:que_jobs].get(:job_class).should == "ModuleJobModule::ModuleJob"

      run_jobs Que.execute("SELECT * FROM que_jobs").first
      $run.should be true
    ensure
      $run = nil
    end
  end

  it "should make a job's argument hashes indifferently accessible" do
    DB[:que_jobs].count.should be 0
    ArgsJob.enqueue 1, 'two', {'array' => [{'number' => 3}]}
    DB[:que_jobs].count.should be 1

    run_jobs Que.execute("SELECT * FROM que_jobs").first
    $passed_args.last[:array].first[:number].should == 3
  end

  it "should skip a job without incident if passed the pk for a job that doesn't exist" do
    DB[:que_jobs].count.should be 0
    run_jobs priority: 1,
             run_at:   Time.now,
             job_id:   587648

    @result_queue.to_a.map{|pk| pk[-1]}.should == [587648]
  end

  it "should only take jobs that meet its priority requirement" do
    @worker.priority = 10

    jobs = (1..20).map { |i| [i, Time.now, i] }

    @job_queue.push *jobs

    sleep_until { @result_queue.to_a.map{|pk| pk[-1]} == (1..10).to_a }

    @job_queue.to_a.should == jobs[10..19]
  end

  describe "when an error is raised" do
    it "should not crash the worker" do
      ErrorJob.enqueue priority: 1
      Que::Job.enqueue priority: 2

      job_ids = DB[:que_jobs].order_by(:priority).select_map(:job_id)
      run_jobs Que.execute("SELECT * FROM que_jobs")
      @result_queue.to_a.map{|pk| pk[-1]}.should == job_ids

      events = logged_messages.select{|m| m['event'] == 'job_errored'}
      events.count.should be 1

      event = events.first
      event['job']['priority'].should == 1
      event['job']['job_id'].should be_an_instance_of Fixnum
      event['error'].should == "ErrorJob!"
    end

    it "should pass it to the error notifier" do
      begin
        error = nil
        Que.error_notifier = proc { |e| error = e }

        ErrorJob.enqueue priority: 1

        run_jobs Que.execute("SELECT * FROM que_jobs")

        error.should be_an_instance_of RuntimeError
        error.message.should == "ErrorJob!"
      ensure
        Que.error_notifier = nil
      end
    end

    it "should not crash the worker if the error notifier is problematic" do
      pending
      begin
        Que.error_notifier = proc { |e| raise "Error notifier error!" }

        ErrorJob.enqueue priority: 1
        Que::Job.enqueue priority: 2

        run_jobs Que.execute("SELECT * FROM que_jobs")

        message = $logger.messages.map{|m| JSON.load(m)}.find{|m| m['event'] == 'error_notifier_errored'}['error_notifier_error']
        message['class'].should == "RuntimeError"
        message['message'].should == "Error notifier error!"
        message['backtrace'].should be_an_instance_of Array
      ensure
        Que.error_notifier = nil
      end
    end

    it "should exponentially back off the job" do
      ErrorJob.enqueue

      run_jobs Que.execute("SELECT * FROM que_jobs")

      DB[:que_jobs].count.should be 1
      job = DB[:que_jobs].first
      job[:error_count].should be 1
      job[:last_error].should == "ErrorJob!"
      job[:run_at].should be_within(3).of Time.now + 4

      DB[:que_jobs].update error_count: 5,
                           run_at:      Time.now - 60

      run_jobs Que.execute("SELECT * FROM que_jobs")

      DB[:que_jobs].count.should be 1
      job = DB[:que_jobs].first
      job[:error_count].should be 6
      job[:last_error].should == "ErrorJob!"
      job[:run_at].should be_within(3).of Time.now + 1299
    end

    it "should respect a custom retry interval" do
      class RetryIntervalJob < ErrorJob
        @retry_interval = 5
      end

      RetryIntervalJob.enqueue

      run_jobs Que.execute("SELECT * FROM que_jobs")

      DB[:que_jobs].count.should be 1
      job = DB[:que_jobs].first
      job[:error_count].should be 1
      job[:last_error].should == "ErrorJob!"
      job[:run_at].should be_within(3).of Time.now + 5

      DB[:que_jobs].update error_count: 5,
                           run_at:      Time.now - 60

      run_jobs Que.execute("SELECT * FROM que_jobs")

      DB[:que_jobs].count.should be 1
      job = DB[:que_jobs].first
      job[:error_count].should be 6
      job[:last_error].should == "ErrorJob!"
      job[:run_at].should be_within(3).of Time.now + 5
    end

    it "should respect a custom retry interval formula" do
      class RetryIntervalFormulaJob < ErrorJob
        @retry_interval = proc { |count| count * 10 }
      end

      RetryIntervalFormulaJob.enqueue

      run_jobs Que.execute("SELECT * FROM que_jobs")

      DB[:que_jobs].count.should be 1
      job = DB[:que_jobs].first
      job[:error_count].should be 1
      job[:last_error].should == "ErrorJob!"
      job[:run_at].should be_within(3).of Time.now + 10

      DB[:que_jobs].update error_count: 5,
                           run_at:      Time.now - 60

      run_jobs Que.execute("SELECT * FROM que_jobs")

      DB[:que_jobs].count.should be 1
      job = DB[:que_jobs].first
      job[:error_count].should be 6
      job[:last_error].should == "ErrorJob!"
      job[:run_at].should be_within(3).of Time.now + 60
    end

    it "should throw an error properly if there's no corresponding job class" do
      DB[:que_jobs].insert job_class: "NonexistentClass"

      run_jobs Que.execute("SELECT * FROM que_jobs")

      DB[:que_jobs].count.should be 1
      job = DB[:que_jobs].first
      job[:error_count].should be 1
      job[:last_error].should =~ /uninitialized constant:? .*NonexistentClass/
      job[:run_at].should be_within(3).of Time.now + 4
    end

    it "should throw an error properly if the corresponding job class doesn't descend from Que::Job" do
      class J
        def run(*args)
        end
      end

      Que.enqueue job_class: "J"

      run_jobs Que.execute("SELECT * FROM que_jobs")

      DB[:que_jobs].count.should be 1
      job = DB[:que_jobs].first
      job[:error_count].should be 1
      job[:run_at].should be_within(3).of Time.now + 4
    end

    context "in a job class that has a custom error handler" do
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

          DB[:que_jobs].count.should be 1
          job = DB[:que_jobs].first
          job[:error_count].should be 1
          job[:last_error].should =~ /\ABlah!/
          job[:run_at].should be_within(3).of Time.now + 42
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

          DB[:que_jobs].count.should be 1
          run_jobs Que.execute("SELECT * FROM que_jobs")
          DB[:que_jobs].count.should be 0
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

          DB[:que_jobs].count.should be 1
          run_jobs Que.execute("SELECT * FROM que_jobs")
          DB[:que_jobs].count.should be 0

          error.should == nil
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
          $error_handler_failed.should == nil

          DB[:que_jobs].count.should be 1
          job = DB[:que_jobs].first
          job[:error_count].should be 1
          job[:last_error].should =~ /\ABlah!/
          job[:run_at].should be_within(3).of Time.now + 4
        ensure
          Que.error_notifier = nil
        end
      end
    end
  end
end
