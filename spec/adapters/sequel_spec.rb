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

  it "with Que.mode = :async should poke a worker after a transaction in which a job was queued commits" do
    pending
  end
end
