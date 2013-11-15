shared_examples "a Que backend" do
  it "should be able to drop and create the jobs table" do
    DB.table_exists?(:que_jobs).should be true
    Que.drop!
    DB.table_exists?(:que_jobs).should be false
    Que.execute "SET client_min_messages TO 'warning'" # Avoid annoying NOTICE messages.
    Que.create!
    DB.table_exists?(:que_jobs).should be true
  end

  it "should be able to clear the jobs table" do
    DB[:que_jobs].insert :type => "Que::Job"
    DB[:que_jobs].count.should be 1
    Que.clear!
    DB[:que_jobs].count.should be 0
  end

  describe "when queueing jobs" do
    it "should be able to queue a job" do
      class QueueableJob < Que::Job
      end

      DB[:que_jobs].count.should be 0
      QueueableJob.queue
      DB[:que_jobs].count.should be 1

      job = DB[:que_jobs].first
      job[:priority].should be 1
      job[:run_at].should be_within(3).of Time.now
      job[:type].should == "QueueableJob"
      JSON.load(job[:args]).should == []
    end

    it "should be able to queue a job with arguments" do
      class ArgumentJob < Que::Job
      end

      DB[:que_jobs].count.should be 0
      ArgumentJob.queue 1, 'two'
      DB[:que_jobs].count.should be 1

      job = DB[:que_jobs].first
      job[:priority].should be 1
      job[:run_at].should be_within(3).of Time.now
      job[:type].should == "ArgumentJob"
      JSON.load(job[:args]).should == [1, 'two']
    end

    it "should be able to queue a job with complex arguments" do
      class ComplexArgumentJob < Que::Job
      end

      DB[:que_jobs].count.should be 0
      ComplexArgumentJob.queue 1, 'two', :string => "string",
                                         :integer => 5,
                                         :array => [1, "two", {:three => 3}],
                                         :hash => {:one => 1, :two => 'two', :three => [3]}

      DB[:que_jobs].count.should be 1

      job = DB[:que_jobs].first
      job[:priority].should be 1
      job[:run_at].should be_within(3).of Time.now
      job[:type].should == "ComplexArgumentJob"
      JSON.load(job[:args]).should == [
        1,
        'two',
        {
          'string' => 'string',
          'integer' => 5,
          'array' => [1, "two", {"three" => 3}],
          'hash' => {'one' => 1, 'two' => 'two', 'three' => [3]}
        }
      ]
    end

    it "should be able to queue a job with a specific time to run" do
      class SchedulableJob < Que::Job
      end

      DB[:que_jobs].count.should be 0
      SchedulableJob.queue 1, :run_at => Time.now + 60
      DB[:que_jobs].count.should be 1

      job = DB[:que_jobs].first
      job[:priority].should be 1
      job[:run_at].should be_within(3).of Time.now + 60
      job[:type].should == "SchedulableJob"
      JSON.load(job[:args]).should == [1]
    end

    it "should be able to queue a job with a specific priority" do
      class PriorityJob < Que::Job
      end

      DB[:que_jobs].count.should be 0
      PriorityJob.queue 1, :priority => 4
      DB[:que_jobs].count.should be 1

      job = DB[:que_jobs].first
      job[:priority].should be 4
      job[:run_at].should be_within(3).of Time.now
      job[:type].should == "PriorityJob"
      JSON.load(job[:args]).should == [1]
    end

    it "should be able to queue a job with queueing options in addition to argument options" do
      class ComplexOptionJob < Que::Job
      end

      DB[:que_jobs].count.should be 0
      ComplexOptionJob.queue 1, :string => "string", :run_at => Time.now + 60, :priority => 4
      DB[:que_jobs].count.should be 1

      job = DB[:que_jobs].first
      job[:priority].should be 4
      job[:run_at].should be_within(3).of Time.now + 60
      job[:type].should == "ComplexOptionJob"
      JSON.load(job[:args]).should == [1, {'string' => 'string'}]
    end

    it "should respect a default (but overridable) priority for the job class" do
      class DefaultPriorityJob < Que::Job
        @default_priority = 3
      end

      DB[:que_jobs].count.should be 0
      DefaultPriorityJob.queue 1
      DefaultPriorityJob.queue 1, :priority => 4
      DB[:que_jobs].count.should be 2

      first, second = DB[:que_jobs].order(:job_id).all

      first[:priority].should be 3
      first[:run_at].should be_within(3).of Time.now
      first[:type].should == "DefaultPriorityJob"
      JSON.load(first[:args]).should == [1]

      second[:priority].should be 4
      second[:run_at].should be_within(3).of Time.now
      second[:type].should == "DefaultPriorityJob"
      JSON.load(second[:args]).should == [1]
    end

    it "should respect a default (but overridable) run_at for the job class" do
      class DefaultRunAtJob < Que::Job
        @default_run_at = -> { Time.now + 60 }
      end

      DB[:que_jobs].count.should be 0
      DefaultRunAtJob.queue 1
      DefaultRunAtJob.queue 1, :run_at => Time.now + 30
      DB[:que_jobs].count.should be 2

      first, second = DB[:que_jobs].order(:job_id).all

      first[:priority].should be 1
      first[:run_at].should be_within(3).of Time.now + 60
      first[:type].should == "DefaultRunAtJob"
      JSON.load(first[:args]).should == [1]

      second[:priority].should be 1
      second[:run_at].should be_within(3).of Time.now + 30
      second[:type].should == "DefaultRunAtJob"
      JSON.load(second[:args]).should == [1]
    end
  end

  describe "when working jobs" do
    it "should pass a job's arguments to the run method and delete it from the database" do
      $passed_number = nil
      $passed_string = nil
      $passed_hash   = nil

      class RunJob < Que::Job
        def run(number, string, hash)
          $passed_number = number
          $passed_string = string
          $passed_hash   = hash
        end
      end

      DB[:que_jobs].count.should be 0
      RunJob.queue 1, 'two', {'three' => 3}
      DB[:que_jobs].count.should be 1
      Que::Job.work.should be_an_instance_of RunJob
      DB[:que_jobs].count.should be 0
      $passed_number.should == 1
      $passed_string.should == 'two'
      $passed_hash.should   == {'three' => 3}

      # Should clear advisory lock.
      DB[:pg_locks].where(:locktype => 'advisory').should be_empty
    end

    it "should make a job's argument hashes indifferently accessible" do
      $passed_args = nil

      class RunJob < Que::Job
        def run(*args)
          $passed_args = args
        end
      end

      DB[:que_jobs].count.should be 0
      RunJob.queue 1, 'two', {'array' => [{'number' => 3}]}
      DB[:que_jobs].count.should be 1
      Que::Job.work.should be_an_instance_of RunJob
      DB[:que_jobs].count.should be 0

      $passed_args.last[:array].first[:number].should == 3

      # Should clear advisory lock.
      DB[:pg_locks].where(:locktype => 'advisory').should be_empty
    end

    it "should not fail if there are no jobs to work" do
      Que::Job.work.should be nil
      DB[:pg_locks].where(:locktype => 'advisory').should be_empty
    end

    it "should prefer a job with a higher priority" do
      class PriorityWorkJob < Que::Job
      end

      PriorityWorkJob.queue :priority => 5
      PriorityWorkJob.queue :priority => 1
      PriorityWorkJob.queue :priority => 5
      DB[:que_jobs].order(:job_id).select_map(:priority).should == [5, 1, 5]

      Que::Job.work.should be_an_instance_of PriorityWorkJob
      DB[:que_jobs].select_map(:priority).should == [5, 5]
    end

    it "should prefer a job that was scheduled to run longer ago" do
      class ScheduledWorkJob < Que::Job
      end

      ScheduledWorkJob.queue :run_at => Time.now - 30
      ScheduledWorkJob.queue :run_at => Time.now - 60
      ScheduledWorkJob.queue :run_at => Time.now - 30

      recent1, old, recent2 = DB[:que_jobs].order(:job_id).select_map(:run_at)

      Que::Job.work.should be_an_instance_of ScheduledWorkJob
      DB[:que_jobs].order_by(:job_id).select_map(:run_at).should == [recent1, recent2]
    end

    it "should prefer a job that was queued earlier, judging by the job_id" do
      class EarlyWorkJob < Que::Job
      end

      run_at = Time.now - 30
      EarlyWorkJob.queue :run_at => run_at
      EarlyWorkJob.queue :run_at => run_at
      EarlyWorkJob.queue :run_at => run_at

      first, second, third = DB[:que_jobs].select_order_map(:job_id)

      Que::Job.work.should be_an_instance_of EarlyWorkJob
      DB[:que_jobs].select_order_map(:job_id).should == [second, third]
    end

    it "should only work a job whose scheduled time to run has passed" do
      class ScheduledWorkJob < Que::Job
      end

      ScheduledWorkJob.queue :run_at => Time.now + 30
      ScheduledWorkJob.queue :run_at => Time.now - 30
      ScheduledWorkJob.queue :run_at => Time.now + 30

      future1, past, future2 = DB[:que_jobs].order(:job_id).select_map(:run_at)

      Que::Job.work.should be_an_instance_of ScheduledWorkJob
      Que::Job.work.should be nil
      DB[:que_jobs].order_by(:job_id).select_map(:run_at).should == [future1, future2]
    end

    it "should lock the job it selects" do
      $q1, $q2 = Queue.new, Queue.new

      class AdvisoryLockJob < Que::Job
        def run(*args)
          $q1.push nil
          $q2.pop
        end
      end

      AdvisoryLockJob.queue
      id = DB[:que_jobs].get(:job_id)
      thread = Thread.new { Que::Job.work }

      $q1.pop
      DB[:pg_locks].where(:locktype => 'advisory', :objid => id).count.should be 1
      $q2.push nil

      thread.join
    end

    it "should not work jobs that are advisory-locked" do
      class AdvisoryLockBlockJob < Que::Job
      end

      AdvisoryLockBlockJob.queue
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

    it "should make it easy to destroy the job within the same transaction as other changes" do
      class TransactionJob < Que::Job
        def run
          destroy
        end
      end

      TransactionJob.queue
      DB[:que_jobs].count.should be 1
      Que::Job.work
      DB[:que_jobs].count.should be 0
    end
  end
end
