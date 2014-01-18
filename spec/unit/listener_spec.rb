require 'spec_helper'

describe Que::Listener do
  it "should exit on its own when informed to stop" do
    listener = Que::Listener.new
    listener.stop
  end

  it "should register its presence or absence in the que_listeners table upon connecting or disconnecting" do
    listener = Que::Listener.new

    sleep_until { DB[:que_listeners].count == 1 }

    record = DB[:que_listeners].first
    record[:ruby_pid].should      == Process.pid
    record[:ruby_hostname].should == Socket.gethostname
    record[:worker_count].should  == 4
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

  it "should receive notifications of new jobs, and immediately lock, work, and unlock them" do
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

  it "should not work jobs that it receives that are already locked" do
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
end
