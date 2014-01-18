require 'spec_helper'

Que.connection = SEQUEL_ADAPTER_DB = Sequel.connect(QUE_URL)
QUE_ADAPTERS[:sequel] = Que.adapter

describe "Que using the Sequel adapter" do
  before { Que.adapter = QUE_ADAPTERS[:sequel] }

  it_behaves_like "a multi-threaded Que adapter"

  it "should use the same connection that Sequel does" do
    begin
      class SequelJob < Que::Job
        def run
          $pid1 = Integer(Que.execute("select pg_backend_pid()").first['pg_backend_pid'])
          $pid2 = Integer(SEQUEL_ADAPTER_DB['select pg_backend_pid()'].get)
        end
      end

      SequelJob.enqueue
      Que::Job.work

      $pid1.should == $pid2
    ensure
      $pid1 = $pid2 = nil
    end
  end

  it "should wake up a Worker after queueing a job in async mode, waiting for a transaction to commit if necessary" do
    Que.mode = :async
    sleep_until { Que::Worker.workers.all? &:sleeping? }

    # Wakes a worker immediately when not in a transaction.
    Que::Job.enqueue
    sleep_until { Que::Worker.workers.all?(&:sleeping?) && DB[:que_jobs].empty? }

    SEQUEL_ADAPTER_DB.transaction do
      Que::Job.enqueue
      Que::Worker.workers.each { |worker| worker.should be_sleeping }
    end
    sleep_until { Que::Worker.workers.all?(&:sleeping?) && DB[:que_jobs].empty? }

    # Do nothing when queueing with a specific :run_at.
    BlockJob.enqueue :run_at => Time.now
    Que::Worker.workers.each { |worker| worker.should be_sleeping }
  end

  it "should be able to tell when it's in a Sequel transaction" do
    Que.adapter.should_not be_in_transaction
    SEQUEL_ADAPTER_DB.transaction do
      Que.adapter.should be_in_transaction
    end
  end
end
