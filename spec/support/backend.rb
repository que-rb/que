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
    it "should be able to queue a job with arguments" do
      pending
    end

    it "should be able to queue a job with a specific time to run" do
      pending
    end

    it "should be able to queue a job with a specific priority" do
      pending
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
