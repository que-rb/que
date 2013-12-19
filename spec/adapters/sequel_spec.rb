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

  it "should safely roll back in-process transactions when using Que.stop!" do
    begin
      class SequelInterruptJob < BlockJob
        def run
          SEQUEL_ADAPTER_DB.transaction do
            Que.execute "INSERT INTO que_jobs (job_id, job_class) VALUES (0, 'Que::Job')"
            super
          end
        end
      end

      SequelInterruptJob.queue
      Que.mode = :async
      $q1.pop
      Que.stop!

      DB[:que_jobs].where(:job_id => 0).should be_empty
    ensure
      # Que.stop! can affect DB connections in an unpredictable fashion, and
      # Sequel's built-in reconnection logic may not be able to recover them.
      # So, force a reconnection for the sake of the other specs...
      SEQUEL_ADAPTER_DB.disconnect

      # ...and that's not even foolproof, because threads may have died with
      # connections checked out.
      SEQUEL_ADAPTER_DB.pool.allocated.each_value(&:close)
      SEQUEL_ADAPTER_DB.pool.allocated.clear
    end
  end
end
