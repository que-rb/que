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
      job[:last_error].should =~ /\AErrorJob!\n/
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
      job[:last_error].should =~ /\AErrorJob!\n/
      job[:run_at].should be_within(3).of Time.now + 1299
    end

    it "should respect a custom retry interval" do
      class RetryIntervalJob < ErrorJob
        @retry_interval = 5
      end

      RetryIntervalJob.enqueue

      result = Que::Job.work
      result[:event].should == :job_errored
      result[:error].should be_an_instance_of RuntimeError
      result[:job][:job_class].should == 'RetryIntervalJob'

      DB[:que_jobs].count.should be 1
      job = DB[:que_jobs].first
      job[:error_count].should be 1
      job[:last_error].should =~ /\AErrorJob!\n/
      job[:run_at].should be_within(3).of Time.now + 5

      DB[:que_jobs].update :error_count => 5,
                           :run_at => Time.now - 60

      result = Que::Job.work
      result[:event].should == :job_errored
      result[:error].should be_an_instance_of RuntimeError
      result[:job][:job_class].should == 'RetryIntervalJob'

      DB[:que_jobs].count.should be 1
      job = DB[:que_jobs].first
      job[:error_count].should be 6
      job[:last_error].should =~ /\AErrorJob!\n/
      job[:run_at].should be_within(3).of Time.now + 5
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
      job[:last_error].should =~ /\AErrorJob!\n/
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
      job[:last_error].should =~ /\AErrorJob!\n/
      job[:run_at].should be_within(3).of Time.now + 60
    end

    it "should pass it to an error handler, if one is defined" do
      begin
        errors = []
        Que.error_handler = proc { |error| errors << error }

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
        Que.error_handler = nil
      end
    end

    it "should not do anything if the error handler itelf throws an error" do
      begin
        Que.error_handler = proc { |error| raise "Another error!" }
        ErrorJob.enqueue

        result = Que::Job.work
        result[:event].should == :job_errored
        result[:error].should be_an_instance_of RuntimeError
      ensure
        Que.error_handler = nil
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
  end
end
