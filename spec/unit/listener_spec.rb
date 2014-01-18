require 'spec_helper'

describe Que::Listener do
  it "should exit on its own when informed to stop" do
    listener = Que::Listener.new
    listener.stop
  end

  it "should register its presence or absence in the que_listeners table upon connecting or disconnecting" do
    worker_count = rand(10) + 1

    listener = Que::Listener.new(:worker_count => worker_count)

    sleep_until { DB[:que_listeners].count == 1 }

    listener.workers.count.should == worker_count

    record = DB[:que_listeners].first
    record[:ruby_pid].should      == Process.pid
    record[:ruby_hostname].should == Socket.gethostname
    record[:worker_count].should  == worker_count
    record[:queue].should         == ''

    listener.stop

    DB[:que_listeners].count.should be 0
  end

  it "should clear invalid listeners from the table when connecting" do
    # Note that we assume that the connection we use to register the bogus
    # listener here will be reused by the actual listener below, in order to
    # spec the cleaning of listeners previously registered by the same
    # connection. This will have to be revisited if the behavior of
    # ConnectionPool (our default adapter) is ever changed.
    Que.execute :register_listener, ['', 3, 0, 'blah1']
    DB[:que_listeners].insert :pid           => 0,
                              :ruby_pid      => 0,
                              :ruby_hostname => 'blah2',
                              :worker_count  => 4,
                              :queue         => ''

    DB[:que_listeners].count.should be 2

    pid = DB[:que_listeners].exclude(:pid => 0).get(:pid)

    listener = Que::Listener.new
    sleep_until { DB[:que_listeners].count == 1 }

    record = DB[:que_listeners].first
    record[:pid].should == pid
    record[:ruby_pid].should == Process.pid

    listener.stop

    DB[:que_listeners].count.should be 0
  end

  it "should do batch polls for jobs on startup"

  it "should do regular batch polls to catch jobs that fall through the cracks"

  it "should exclude jobs that it has already locked from its batch polling"

  it "should clear its queue of jobs when told to shut down"

  it "should clear any advisory locks it has taken when told to shut down"

  it "should respect a custom setting for wake_interval"

  it "should respect a custom setting for queue_size"

  it "should log what it's doing"

  describe "when receiving a NOTIFY of a new job" do
    it "should immediately lock, work, and unlock them" do
      DB[:que_jobs].count.should be 0
      listener = Que::Listener.new
      sleep_until { DB[:que_listeners].count == 1 }

      BlockJob.queue
      $q1.pop

      locks = DB[:pg_locks].where(:locktype => 'advisory').all
      locks.count.should be 1
      locks.first[:objid].should == DB[:que_jobs].get(:job_id)

      $q2.push nil
      sleep_until { DB[:que_jobs].count == 0 }
      sleep_until { DB[:pg_locks].where(:locktype => 'advisory').count == 0 }

      listener.stop
    end

    it "should not work jobs that are already locked" do
      DB[:que_jobs].count.should be 0
      listener = Que::Listener.new
      sleep_until { DB[:que_listeners].count == 1 }

      id = nil
      q1, q2 = Queue.new, Queue.new
      t = Thread.new do
        Que.adapter.checkout do
          # NOTIFY won't propagate until transaction commits.
          Que.execute "BEGIN"
          Que::Job.queue
          id = Que.execute("SELECT job_id FROM que_jobs LIMIT 1").first[:job_id].to_i
          Que.execute "SELECT pg_advisory_lock($1)", [id]
          Que.execute "COMMIT"
          q1.push nil
          q2.pop
          Que.execute "SELECT pg_advisory_unlock($1)", [id]
        end
      end

      q1.pop
      listener.stop
      q2.push nil

      DB[:que_jobs].select_map(:job_id).should == [id]
    end

    it "should not lock the job if it has already been locked by the listener"

    it "should not lock or work it if it is scheduled to be worked at a later date"

    it "of low importance should not lock them or add them to the JobQueue if it is full"

    it "of significant importance should lock and add them to the JobQueue and dequeue/unlock the least important ones to make room"

    it "should log what it's doing"
  end
end
