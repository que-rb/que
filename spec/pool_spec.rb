require 'spec_helper'

describe "Managing the Worker pool" do
  it "Que.mode = :sync should make jobs run in the same thread as they are queued" do
    Que.mode = :sync

    ArgsJob.queue(5, :testing => "synchronous").should be_an_instance_of ArgsJob
    $passed_args.should == [5, {'testing' => "synchronous"}]
    DB[:que_jobs].count.should be 0

    $logger.messages.length.should be 1
    $logger.messages[0].should =~ /\AWorked job in/
  end

  describe "Que.mode = :async" do
    it "should spin up 4 workers" do
      pending
    end

    it "then Que.worker_count = 2 should gracefully decrease the number of workers" do
      pending
    end

    it "then Que.worker_count = 5 should gracefully increase the number of workers" do
      pending
    end

    it "then Que.mode = :off should gracefully shut down workers" do
      pending
    end

    it "then Que::Worker.poke! should wake up a single worker" do
      pending
    end

    it "then Que::Worker.poke_all! should wake up all workers" do
      pending
    end

    it "should poke a worker every Que.sleep_period seconds" do
      pending
    end
  end
end
