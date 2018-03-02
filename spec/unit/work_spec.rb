# frozen_string_literal: true

require 'spec_helper'

describe Que::Job, '.work' do
  it "should pass a job's arguments to the run method and delete it from the database" do
    ArgsJob.enqueue 1, 'two', {'three' => 3}
    DB[:que_jobs].count.should be 1

    result = Que::Job.work
    result[:event].should == :job_worked
    result[:job][:job_class].should == 'ArgsJob'

    DB[:que_jobs].count.should be 0
    $passed_args.should == [1, 'two', {'three' => 3}]
  end

  it "should respect a custom json converter when processing the job's arguments" do
    ArgsJob.enqueue 1, 'two', {'three' => 3}
    DB[:que_jobs].count.should be 1

    begin
      Que.json_converter = Que::SYMBOLIZER

      result = Que::Job.work
      result[:event].should == :job_worked
      result[:job][:job_class].should == 'ArgsJob'

      DB[:que_jobs].count.should be 0
      $passed_args.should == [1, 'two', {:three => 3}]
    ensure
      Que.json_converter = Que::INDIFFERENTIATOR
    end
  end

  it "should default to only working jobs without a named queue" do
    Que::Job.enqueue 1, :queue => 'other_queue'
    Que::Job.enqueue 2

    result = Que::Job.work
    result[:event].should == :job_worked
    result[:job][:args].should == [2]

    result = Que::Job.work
    result[:event].should == :job_unavailable
  end

  it "should accept the name of a single queue to pull jobs from" do
    Que::Job.enqueue 1, :queue => 'other_queue'
    Que::Job.enqueue 2, :queue => 'other_queue'
    Que::Job.enqueue 3

    result = Que::Job.work(:other_queue)
    result[:event].should == :job_worked
    result[:job][:args].should == [1]

    result = Que::Job.work('other_queue')
    result[:event].should == :job_worked
    result[:job][:args].should == [2]

    result = Que::Job.work(:other_queue)
    result[:event].should == :job_unavailable
  end

  it "should make a job's argument hashes indifferently accessible" do
    DB[:que_jobs].count.should be 0
    ArgsJob.enqueue 1, 'two', {'array' => [{'number' => 3}]}
    DB[:que_jobs].count.should be 1

    result = Que::Job.work
    result[:event].should == :job_worked
    result[:job][:job_class].should == 'ArgsJob'

    DB[:que_jobs].count.should be 0

    $passed_args.last[:array].first[:number].should == 3
  end

  it "should not fail if there are no jobs to work" do
    Que::Job.work[:event].should be :job_unavailable
  end

  it "should prefer a job with a higher priority" do
    # 1 is highest priority.
    [5, 4, 3, 2, 1, 2, 3, 4, 5].map{|p| Que::Job.enqueue :priority => p}
    DB[:que_jobs].order(:job_id).select_map(:priority).should == [5, 4, 3, 2, 1, 2, 3, 4, 5]

    result = Que::Job.work
    result[:event].should == :job_worked
    result[:job][:job_class].should == 'Que::Job'
    DB[:que_jobs].select_map(:priority).should == [5, 4, 3, 2, 2, 3, 4, 5]
  end

  it "should prefer a job that was scheduled to run longer ago when priorities are equal" do
    Que::Job.enqueue :run_at => Time.now - 30
    Que::Job.enqueue :run_at => Time.now - 60
    Que::Job.enqueue :run_at => Time.now - 30

    recent1, old, recent2 = DB[:que_jobs].order(:job_id).select_map(:run_at)

    result = Que::Job.work
    result[:event].should == :job_worked
    result[:job][:job_class].should == 'Que::Job'
    DB[:que_jobs].order_by(:job_id).select_map(:run_at).should == [recent1, recent2]
  end

  it "should prefer a job that was queued earlier when priorities and run_ats are equal" do
    run_at = Time.now - 30
    Que::Job.enqueue :run_at => run_at
    Que::Job.enqueue :run_at => run_at
    Que::Job.enqueue :run_at => run_at

    first, second, third = DB[:que_jobs].select_order_map(:job_id)

    result = Que::Job.work
    result[:event].should == :job_worked
    result[:job][:job_class].should == 'Que::Job'
    DB[:que_jobs].select_order_map(:job_id).should == [second, third]
  end

  it "should only work a job whose scheduled time to run has passed" do
    Que::Job.enqueue :run_at => Time.now + 30
    Que::Job.enqueue :run_at => Time.now - 30
    Que::Job.enqueue :run_at => Time.now + 30

    future1, past, future2 = DB[:que_jobs].order(:job_id).select_map(:run_at)

    result = Que::Job.work
    result[:event].should == :job_worked
    result[:job][:job_class].should == 'Que::Job'
    Que::Job.work[:event].should be :job_unavailable
    DB[:que_jobs].order_by(:job_id).select_map(:run_at).should == [future1, future2]
  end

  it "should lock the job it selects" do
    BlockJob.enqueue
    id = DB[:que_jobs].get(:job_id)
    thread = Thread.new { Que::Job.work }

    $q1.pop
    DB[:pg_locks].where(:locktype => 'advisory').select_map(:objid).should == [id]
    $q2.push nil

    thread.join
  end

  it "should skip jobs that are advisory-locked" do
    Que::Job.enqueue :priority => 2
    Que::Job.enqueue :priority => 1
    Que::Job.enqueue :priority => 3
    id = DB[:que_jobs].where(:priority => 1).get(:job_id)

    begin
      DB.select{pg_advisory_lock(id)}.single_value

      result = Que::Job.work
      result[:event].should == :job_worked
      result[:job][:job_class].should == 'Que::Job'

      DB[:que_jobs].order_by(:job_id).select_map(:priority).should == [1, 3]
    ensure
      DB.select{pg_advisory_unlock(id)}.single_value
    end
  end

  it "should handle subclasses of other jobs" do
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
    result = Que::Job.work
    result[:event].should == :job_worked
    result[:job][:job_class].should == 'SubClassJob'
    $job_spec_result.should == [:sub]

    $job_spec_result = []
    SubSubClassJob.enqueue
    DB[:que_jobs].select_map(:priority).should == [4]
    result = Que::Job.work
    result[:event].should == :job_worked
    result[:job][:job_class].should == 'SubSubClassJob'
    $job_spec_result.should == [:sub, :subsub]
  end

  it "should handle namespaced subclasses" do
    module ModuleJobModule
      class ModuleJob < Que::Job
      end
    end

    ModuleJobModule::ModuleJob.enqueue
    DB[:que_jobs].get(:job_class).should == "ModuleJobModule::ModuleJob"

    result = Que::Job.work
    result[:event].should == :job_worked
    result[:job][:job_class].should == 'ModuleJobModule::ModuleJob'
  end

  it "should make it easy to destroy the job within the same transaction as other changes" do
    class DestroyJob < Que::Job
      def run
        destroy
      end
    end

    DestroyJob.enqueue
    DB[:que_jobs].count.should be 1
    Que::Job.work
    DB[:que_jobs].count.should be 0
  end

  describe "when encountering an error" do
    it "should exponentially back off the job" do
      ErrorJob.enqueue

      result = Que::Job.work
      result[:event].should == :job_errored
      result[:error].should be_an_instance_of RuntimeError
      result[:job][:job_class].should == 'ErrorJob'

      DB[:que_jobs].count.should be 1
      job = DB[:que_jobs].first
      job[:error_count].should be 1
      job[:last_error].should =~ /\ARuntimeError: ErrorJob!/
      job[:run_at].should be_within(3).of Time.now + 4

      DB[:que_jobs].update :error_count => 5,
                           :run_at => Time.now - 60

      result = Que::Job.work
      result[:event].should == :job_errored
      result[:error].should be_an_instance_of RuntimeError
      result[:job][:job_class].should == 'ErrorJob'

      DB[:que_jobs].count.should be 1
      job = DB[:que_jobs].first
      job[:error_count].should be 6
      job[:last_error].should =~ /\ARuntimeError: ErrorJob!/
      job[:run_at].should be_within(3).of Time.now + 1299
    end

    it "should respect a custom retry interval" do
      class RetryIntervalJob < ErrorJob
        @retry_interval = 3155760000000 # 100,000 years from now
      end

      RetryIntervalJob.enqueue

      result = Que::Job.work
      result[:event].should == :job_errored
      result[:error].should be_an_instance_of RuntimeError
      result[:job][:job_class].should == 'RetryIntervalJob'

      DB[:que_jobs].count.should be 1
      job = DB[:que_jobs].first
      job[:error_count].should be 1
      job[:last_error].should =~ /\ARuntimeError: ErrorJob!/
      job[:run_at].to_f.should be_within(3).of Time.now.to_f + RetryIntervalJob.retry_interval

      DB[:que_jobs].update :error_count => 5,
                           :run_at => Time.now - 60

      result = Que::Job.work
      result[:event].should == :job_errored
      result[:error].should be_an_instance_of RuntimeError
      result[:job][:job_class].should == 'RetryIntervalJob'

      DB[:que_jobs].count.should be 1
      job = DB[:que_jobs].first
      job[:error_count].should be 6
      job[:last_error].should =~ /\ARuntimeError: ErrorJob!/
      job[:run_at].to_f.should be_within(3).of Time.now.to_f + RetryIntervalJob.retry_interval
    end

    it "should respect a custom retry interval formula" do
      class RetryIntervalFormulaJob < ErrorJob
        @retry_interval = proc { |count| count * 10 }
      end

      RetryIntervalFormulaJob.enqueue

      result = Que::Job.work
      result[:event].should == :job_errored
      result[:error].should be_an_instance_of RuntimeError
      result[:job][:job_class].should == 'RetryIntervalFormulaJob'

      DB[:que_jobs].count.should be 1
      job = DB[:que_jobs].first
      job[:error_count].should be 1
      job[:last_error].should =~ /\ARuntimeError: ErrorJob!/
      job[:run_at].should be_within(3).of Time.now + 10

      DB[:que_jobs].update :error_count => 5,
                           :run_at => Time.now - 60

      result = Que::Job.work
      result[:event].should == :job_errored
      result[:error].should be_an_instance_of RuntimeError
      result[:job][:job_class].should == 'RetryIntervalFormulaJob'

      DB[:que_jobs].count.should be 1
      job = DB[:que_jobs].first
      job[:error_count].should be 6
      job[:last_error].should =~ /\ARuntimeError: ErrorJob!/
      job[:run_at].should be_within(3).of Time.now + 60
    end

    it "should pass it to an error notifier, if one is defined" do
      begin
        errors = []
        Que.error_notifier = proc { |error| errors << error }

        ErrorJob.enqueue

        result = Que::Job.work
        result[:event].should == :job_errored
        result[:error].should be_an_instance_of RuntimeError
        result[:job][:job_class].should == 'ErrorJob'

        errors.count.should be 1
        error = errors[0]
        error.should be_an_instance_of RuntimeError
        error.message.should == "ErrorJob!"
      ensure
        Que.error_notifier = nil
      end
    end

    it "should pass job to an error notifier, if one is defined" do
      begin
        jobs = []
        Que.error_notifier = proc { |error, job| jobs << job }

        ErrorJob.enqueue
        result = Que::Job.work

        jobs.count.should be 1
        job = jobs[0]
        job.should be result[:job]
      ensure
        Que.error_notifier = nil
      end
    end

    it "should not do anything if the error notifier itelf throws an error" do
      begin
        Que.error_notifier = proc { |error| raise "Another error!" }
        ErrorJob.enqueue

        result = Que::Job.work
        result[:event].should == :job_errored
        result[:error].should be_an_instance_of RuntimeError
      ensure
        Que.error_notifier = nil
      end
    end

    it "should throw an error properly if there's no corresponding job class" do
      DB[:que_jobs].insert :job_class => "NonexistentClass"

      result = Que::Job.work
      result[:event].should == :job_errored
      result[:error].should be_an_instance_of NameError
      result[:job][:job_class].should == 'NonexistentClass'

      DB[:que_jobs].count.should be 1
      job = DB[:que_jobs].first
      job[:error_count].should be 1
      job[:last_error].should =~ /uninitialized constant:? NonexistentClass/
      job[:run_at].should be_within(3).of Time.now + 4
    end

    it "should throw an error properly if the corresponding job class doesn't descend from Que::Job" do
      class J
        def run(*args)
        end
      end

      Que.enqueue :job_class => "J"

      result = Que::Job.work
      result[:event].should == :job_errored
      result[:job][:job_class].should == 'J'

      DB[:que_jobs].count.should be 1
      job = DB[:que_jobs].first
      job[:error_count].should be 1
      job[:run_at].should be_within(3).of Time.now + 4
    end

    it "should use the class name of the exception if its message is blank when setting last_error" do
      class BlankExceptionMessageJob < Que::Job
        def self.error
          @error ||= RuntimeError.new("")
        end

        def run
          raise self.class.error
        end
      end

      BlankExceptionMessageJob.enqueue
      result = Que::Job.work
      result[:event].should == :job_errored
      job = DB[:que_jobs].first
      job[:error_count].should be 1
      last_error_lines = job[:last_error].split("\n")
      last_error_lines.should == %w[RuntimeError] + BlankExceptionMessageJob.error.backtrace
    end

    it "should use the class name of the exception if its message is blank when setting last_error" do
      class LongExceptionMessageJob < Que::Job
        def self.error
          @error ||= RuntimeError.new("a" * 500)
        end

        def run
          raise self.class.error
        end
      end

      LongExceptionMessageJob.enqueue
      result = Que::Job.work
      result[:event].should == :job_errored
      job = DB[:que_jobs].first
      job[:error_count].should be 1
      last_error_lines = job[:last_error].split("\n")
      last_error_lines.should == ["RuntimeError: #{'a' * 486}"] + LongExceptionMessageJob.error.backtrace
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

          result = Que::Job.work
          result[:event].should == :job_errored
          result[:error].should be_an_instance_of RuntimeError
          result[:job][:job_class].should == 'CustomRetryIntervalJob'

          DB[:que_jobs].count.should be 1
          job = DB[:que_jobs].first
          job[:error_count].should be 1

          lines = job[:last_error].split("\n")
          lines[0].should == "RuntimeError: Blah!"
          lines[1].should =~ /work_spec/
          job[:run_at].should be_within(3).of Time.now + 42

          error.should == result[:error]
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

          result = Que::Job.work
          result[:event].should == :job_errored
          result[:error].should be_an_instance_of RuntimeError
          result[:job][:job_class].should == 'CustomRetryIntervalJob'

          DB[:que_jobs].count.should be 0

          error.should == result[:error]
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

          result = Que::Job.work
          result[:event].should == :job_errored
          result[:error].should be_an_instance_of RuntimeError
          result[:job][:job_class].should == 'CustomRetryIntervalJob'

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

          result = Que::Job.work
          result[:event].should == :job_errored
          result[:error].should be_an_instance_of RuntimeError
          result[:job][:job_class].should == 'CustomRetryIntervalJob'

          $error_handler_failed.should == nil

          DB[:que_jobs].count.should be 1
          job = DB[:que_jobs].first
          job[:error_count].should be 1
          job[:last_error].should =~ /\ARuntimeError: Blah!/
          job[:run_at].should be_within(3).of Time.now + 4

          error.should == result[:error]
        ensure
          Que.error_notifier = nil
        end
      end
    end
  end
end
