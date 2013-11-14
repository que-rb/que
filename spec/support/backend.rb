shared_examples "a Que backend" do
  it "should be able to drop and create the jobs table" do
    DB.table_exists?(:que_jobs).should be true
    Que.drop!
    DB.table_exists?(:que_jobs).should be false
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
      pending
    end

    it "should prefer a job with a higher priority" do
      pending
    end

    it "should prefer a job that was scheduled to run longer ago" do
      pending
    end

    it "should prefer a job that was queued earlier, judging by the job_id" do
      pending
    end

    it "should only work a job whose scheduled time to run has passed" do
      pending
    end

    it "should lock the job it selects" do
      pending
    end

    it "should not work jobs that are advisory-locked" do
      pending
    end

    it "should respect a Job::Retry error and leave the job to be processed over again" do
      pending
    end

    it "should handle subclasses of other jobs" do
      pending
    end
  end
end
