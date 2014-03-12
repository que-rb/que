require 'spec_helper'

Que.connection = SEQUEL_ADAPTER_DB = Sequel.connect(QUE_URL)
QUE_POOLS[:sequel] = Que.pool

describe "Que using Sequel" do
  before { Que.pool = QUE_POOLS[:sequel] }

  it_behaves_like "a Que pool"

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
    Que.should_not be_in_transaction
    SEQUEL_ADAPTER_DB.transaction do
      Que.should be_in_transaction
    end
  end
end
