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
      job[:run_at].should be_within(1).of Time.now
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
      job[:run_at].should be_within(1).of Time.now
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
      job[:run_at].should be_within(1).of Time.now
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
      SchedulableJob.queue 1, :string => "string", :run_at => Time.now + 60
      DB[:que_jobs].count.should be 1

      job = DB[:que_jobs].first
      job[:priority].should be 1
      job[:run_at].should be_within(1).of Time.now + 60
      job[:type].should == "SchedulableJob"
      JSON.load(job[:args]).should == [1, {'string' => 'string'}]
    end

    it "should be able to queue a job with a specific priority" do
      class PriorityJob < Que::Job
      end

      DB[:que_jobs].count.should be 0
      PriorityJob.queue 1, :string => "string", :priority => 4
      DB[:que_jobs].count.should be 1

      job = DB[:que_jobs].first
      job[:priority].should be 4
      job[:run_at].should be_within(1).of Time.now
      job[:type].should == "PriorityJob"
      JSON.load(job[:args]).should == [1, {'string' => 'string'}]
    end

    it "should be able to queue a job with queueing options in addition to argument options" do
      pending
    end

    it "should respect a default (but overridable) priority for the job class" do
      pending
    end

    it "should respect a default (but overridable) run_at for the job class" do
      pending
    end

    it "should raise an error if given arguments that can't convert to and from JSON unambiguously" do
      pending
    end
  end
end
