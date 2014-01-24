require 'spec_helper'

describe Que::Locker do
  it "should exit on its own when informed to stop" do
    Que::Locker.new.stop
  end

  it "should register its presence or absence in the que_lockers table upon connecting or disconnecting" do
    worker_count = rand(10) + 1

    locker = Que::Locker.new(:worker_count => worker_count, :listening => true)

    sleep_until { DB[:que_lockers].count == 1 }

    locker.workers.count.should == worker_count

    record = DB[:que_lockers].first
    record[:ruby_pid].should      == Process.pid
    record[:ruby_hostname].should == Socket.gethostname
    record[:worker_count].should  == worker_count
    record[:queue].should         == ''
    record[:listening].should     == true

    locker.stop

    DB[:que_lockers].count.should be 0
  end

  it "should clear invalid lockers from the table when connecting" do
    # Note that we assume that the connection we use to register the bogus
    # locker here will be reused by the actual locker below, in order to
    # spec the cleaning of lockers previously registered by the same
    # connection. This will have to be revisited if the behavior of
    # ConnectionPool (our default adapter) is ever changed.
    Que.execute :register_locker, ['', 3, 0, 'blah1', true]
    DB[:que_lockers].insert :pid           => 0,
                            :ruby_pid      => 0,
                            :ruby_hostname => 'blah2',
                            :worker_count  => 4,
                            :queue         => '',
                            :listening     => true

    DB[:que_lockers].count.should be 2

    pid = DB[:que_lockers].exclude(:pid => 0).get(:pid)

    locker = Que::Locker.new
    sleep_until { DB[:que_lockers].count == 1 }

    record = DB[:que_lockers].first
    record[:pid].should == pid
    record[:ruby_pid].should == Process.pid

    locker.stop

    DB[:que_lockers].count.should be 0
  end

  it "should respect priority settings for workers"

  it "should do batch polls for jobs on startup"

  it "should do batch polls at wake_interval to catch jobs that fall through the cracks"

  describe "when doing a batch poll" do
    it "should not lock jobs a second time"

    it "should respect a maximum_queue_size setting"

    it "should consider priority settings for workers"

    it "should log what it's doing"
  end

  describe "when receiving a NOTIFY of a new job" do
    it "should immediately lock, work, and unlock them" do
      DB[:que_jobs].count.should be 0
      locker = Que::Locker.new :listening => true
      sleep_until { DB[:que_lockers].count == 1 }

      BlockJob.enqueue
      $q1.pop

      locks = DB[:pg_locks].where(:locktype => 'advisory').all
      locks.count.should be 1
      locks.first[:objid].should == DB[:que_jobs].get(:job_id)

      $q2.push nil
      sleep_until { DB[:que_jobs].count == 0 }
      sleep_until { DB[:pg_locks].where(:locktype => 'advisory').count == 0 }

      locker.stop
    end

    it "should not work jobs that are already locked" do
      DB[:que_jobs].count.should be 0
      locker = Que::Locker.new :listening => true
      sleep_until { DB[:que_lockers].count == 1 }

      id = nil
      q1, q2 = Queue.new, Queue.new
      t = Thread.new do
        Que.adapter.checkout do
          # NOTIFY won't propagate until transaction commits.
          Que.execute "BEGIN"
          Que::Job.enqueue
          id = Que.execute("SELECT job_id FROM que_jobs LIMIT 1").first[:job_id].to_i
          Que.execute "SELECT pg_advisory_lock($1)", [id]
          Que.execute "COMMIT"
          q1.push nil
          q2.pop
          Que.execute "SELECT pg_advisory_unlock($1)", [id]
        end
      end

      q1.pop
      locker.stop
      q2.push nil

      DB[:que_jobs].select_map(:job_id).should == [id]
    end

    it "should not lock jobs a second time"

    it "should not lock or work it if it is scheduled to be worked at a later date"

    it "of low importance should not lock them or add them to the JobQueue if it is full"

    it "of significant importance should lock and add them to the JobQueue and dequeue/unlock the least important one to make room"

    it "should log what it's doing"
  end

  describe "when told to shut down" do
    it "should stop listening and batch polling"

    it "should remove and unlock all the jobs in its queue"

    it "should wait for its currently running jobs to finish before returning"

    it "should log what it's doing"
  end
end
