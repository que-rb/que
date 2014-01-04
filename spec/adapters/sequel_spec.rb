require 'spec_helper'

Que.connection = SEQUEL_ADAPTER_DB = Sequel.connect(QUE_URL)
QUE_ADAPTERS[:sequel] = Que.adapter

describe "Que using the Sequel adapter" do
  before { Que.adapter = QUE_ADAPTERS[:sequel] }

  it_behaves_like "a Que adapter"
  it_behaves_like "a multithreaded Que adapter"

  it "should use the same connection that Sequel does" do
    class SequelJob < Que::Job
      def run
        $pid1 = Que.execute("SELECT pg_backend_pid()").first['pg_backend_pid'].to_i
        $pid2 = SEQUEL_ADAPTER_DB.get{pg_backend_pid{}}
      end
    end

    SequelJob.queue
    Que::Job.work

    $pid1.should == $pid2
  end

  it "should wake up a Worker after queueing a job in async mode, waiting for a transaction to commit if necessary" do
    Que.mode = :async
    sleep_until { Que::Worker.workers.all? &:sleeping? }

    # Wakes a worker immediately when not in a transaction.
    Que::Job.queue
    sleep_until { Que::Worker.workers.all?(&:sleeping?) && DB[:que_jobs].empty? }

    SEQUEL_ADAPTER_DB.transaction do
      Que::Job.queue
      Que::Worker.workers.each { |worker| worker.should be_sleeping }
    end
    sleep_until { Que::Worker.workers.all?(&:sleeping?) && DB[:que_jobs].empty? }

    # Do nothing when queueing with a specific :run_at.
    BlockJob.queue :run_at => Time.now
    Que::Worker.workers.each { |worker| worker.should be_sleeping }
  end
end
