require 'spec_helper'

describe Que::Job, '.work' do
  it "should pass a job's arguments to the run method and delete it from the database" do
    ArgsJob.queue 1, 'two', {'three' => 3}
    DB[:que_jobs].count.should be 1
    Que::Job.work.should be_an_instance_of ArgsJob
    DB[:que_jobs].count.should be 0
    $passed_args.should == [1, 'two', {'three' => 3}]

    # Should clear advisory lock.
    DB[:pg_locks].where(:locktype => 'advisory').should be_empty
  end

  it "should make a job's argument hashes indifferently accessible" do
    DB[:que_jobs].count.should be 0
    ArgsJob.queue 1, 'two', {'array' => [{'number' => 3}]}
    DB[:que_jobs].count.should be 1
    Que::Job.work.should be_an_instance_of ArgsJob
    DB[:que_jobs].count.should be 0

    $passed_args.last[:array].first[:number].should == 3

    # Should clear advisory lock.
    DB[:pg_locks].where(:locktype => 'advisory').should be_empty
  end

  it "should not fail if there are no jobs to work" do
    Que::Job.work.should be nil
    DB[:pg_locks].where(:locktype => 'advisory').should be_empty
  end

  it "should write messages to the logger" do
    Que::Job.queue
    Que::Job.work

    $logger.messages.length.should == 1
    $logger.messages[0].should =~ /\AWorked job in/
  end

  it "should not fail if there's no logger assigned" do
    begin
      Que.logger = nil

      Que::Job.queue
      Que::Job.work
    ensure
      Que.logger = $logger
    end
  end

  it "should prefer a job with a higher priority" do
    Que::Job.queue :priority => 5
    Que::Job.queue :priority => 1
    Que::Job.queue :priority => 5
    DB[:que_jobs].order(:job_id).select_map(:priority).should == [5, 1, 5]

    Que::Job.work.should be_an_instance_of Que::Job
    DB[:que_jobs].select_map(:priority).should == [5, 5]
  end

  it "should prefer a job that was scheduled to run longer ago" do
    Que::Job.queue :run_at => Time.now - 30
    Que::Job.queue :run_at => Time.now - 60
    Que::Job.queue :run_at => Time.now - 30

    recent1, old, recent2 = DB[:que_jobs].order(:job_id).select_map(:run_at)

    Que::Job.work.should be_an_instance_of Que::Job
    DB[:que_jobs].order_by(:job_id).select_map(:run_at).should == [recent1, recent2]
  end

  it "should prefer a job that was queued earlier, judging by the job_id" do
    run_at = Time.now - 30
    Que::Job.queue :run_at => run_at
    Que::Job.queue :run_at => run_at
    Que::Job.queue :run_at => run_at

    first, second, third = DB[:que_jobs].select_order_map(:job_id)

    Que::Job.work.should be_an_instance_of Que::Job
    DB[:que_jobs].select_order_map(:job_id).should == [second, third]
  end

  it "should only work a job whose scheduled time to run has passed" do
    Que::Job.queue :run_at => Time.now + 30
    Que::Job.queue :run_at => Time.now - 30
    Que::Job.queue :run_at => Time.now + 30

    future1, past, future2 = DB[:que_jobs].order(:job_id).select_map(:run_at)

    Que::Job.work.should be_an_instance_of Que::Job
    Que::Job.work.should be nil
    DB[:que_jobs].order_by(:job_id).select_map(:run_at).should == [future1, future2]
  end

  it "should lock the job it selects" do
    BlockJob.queue
    id = DB[:que_jobs].get(:job_id)
    thread = Thread.new { Que::Job.work }

    $q1.pop
    DB[:pg_locks].where(:locktype => 'advisory', :objid => id).count.should be 1
    $q2.push nil

    thread.join
  end

  it "should not work jobs that are advisory-locked" do
    Que::Job.queue
    id = DB[:que_jobs].get(:job_id)

    begin
      DB.select{pg_advisory_lock(id)}.single_value
      Que::Job.work.should be nil
    ensure
      DB.select{pg_advisory_unlock(id)}.single_value
    end
  end

  it "should handle subclasses of other jobs" do
    class SubClassJob < Que::Job
      @default_priority = 2

      def run
        $job_spec_result << :sub
      end
    end

    class SubSubClassJob < SubClassJob
      @default_priority = 4

      def run
        super
        $job_spec_result << :subsub
      end
    end

    $job_spec_result = []
    SubClassJob.queue
    DB[:que_jobs].select_map(:priority).should == [2]
    Que::Job.work.should be_an_instance_of SubClassJob
    $job_spec_result.should == [:sub]

    $job_spec_result = []
    SubSubClassJob.queue
    DB[:que_jobs].select_map(:priority).should == [4]
    Que::Job.work.should be_an_instance_of SubSubClassJob
    $job_spec_result.should == [:sub, :subsub]
  end

  it "should handle namespaced subclasses" do
    module ModuleJobModule
      class ModuleJob < Que::Job
      end
    end

    ModuleJobModule::ModuleJob.queue
    DB[:que_jobs].get(:job_class).should == "ModuleJobModule::ModuleJob"
    Que::Job.work.should be_an_instance_of ModuleJobModule::ModuleJob
  end

  it "should make it easy to destroy the job within the same transaction as other changes" do
    class DestroyJob < Que::Job
      def run
        destroy
      end
    end

    DestroyJob.queue
    DB[:que_jobs].count.should be 1
    Que::Job.work
    DB[:que_jobs].count.should be 0
  end

  describe "when encountering an error" do
    it "should exponentially back off the job" do
      ErrorJob.queue
      Que::Job.work.should be true

      DB[:que_jobs].count.should be 1
      job = DB[:que_jobs].first
      job[:error_count].should be 1
      job[:last_error].should =~ /\AErrorJob!\n/
      job[:run_at].should be_within(3).of Time.now + 4

      DB[:que_jobs].update :error_count => 5,
                           :run_at => Time.now - 60

      Que::Job.work.should be true

      DB[:que_jobs].count.should be 1
      job = DB[:que_jobs].first
      job[:error_count].should be 6
      job[:last_error].should =~ /\AErrorJob!\n/
      job[:run_at].should be_within(3).of Time.now + 1299
    end

    it "should pass it to an error handler, if one is defined" do
      begin
        errors = []
        Que.error_handler = proc { |error| errors << error }

        ErrorJob.queue
        Que::Job.work.should be true

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
        ErrorJob.queue
        Que::Job.work.should be true
      ensure
        Que.error_handler = nil
      end
    end

    it "should return false if the job throws a postgres error" do
      class PGErrorJob < Que::Job
        def run
          Que.execute "bad SQL syntax"
        end
      end

      PGErrorJob.queue
      Que::Job.work.should be false
    end

    it "should behave sensibly if there's no corresponding job class" do
      DB[:que_jobs].insert :job_class => "NonexistentClass"
      Que::Job.work.should be true
      DB[:que_jobs].count.should be 1
      job = DB[:que_jobs].first
      job[:error_count].should be 1
      job[:last_error].should =~ /\Auninitialized constant NonexistentClass/
      job[:run_at].should be_within(3).of Time.now + 4
    end
  end
end
