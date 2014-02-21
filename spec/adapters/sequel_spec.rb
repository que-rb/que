require 'spec_helper'

SEQUEL_ADAPTER_DB = Sequel.connect(QUE_URL)
Que.connection = SEQUEL_ADAPTER_DB.method(:synchronize)
QUE_ADAPTERS[:sequel] = Que.adapter

describe "Que using the Sequel adapter" do
  before { Que.adapter = QUE_ADAPTERS[:sequel] }

  it_behaves_like "a Que adapter"

  it "should use the same connection that Sequel does" do
    begin
      class SequelJob < Que::Job
        def run
          $pid1 = Que.execute("SELECT pg_backend_pid()").first[:pg_backend_pid]
          $pid2 = SEQUEL_ADAPTER_DB.get{pg_backend_pid{}}
        end
      end

      SequelJob.enqueue
      locker = Que::Locker.new

      sleep_until { Integer === $pid1 && Integer === $pid2 }
      $pid1.should == $pid2
    ensure
      $pid1 = $pid2 = nil
      locker.stop if locker
    end
  end

  it "should be able to tell when it's in a Sequel transaction" do
    Que.adapter.should_not be_in_transaction
    SEQUEL_ADAPTER_DB.transaction do
      Que.adapter.should be_in_transaction
    end
  end
end
