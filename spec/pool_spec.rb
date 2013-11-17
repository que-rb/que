require 'spec_helper'

describe "Managing the Worker pool" do
  it "Que.mode = :sync should make jobs run in the same thread as they are queued" do
    pending
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
