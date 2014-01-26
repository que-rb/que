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

  it "should do batch polls for jobs on startup" do
    job1, job2 = BlockJob.enqueue, BlockJob.enqueue
    job3       = Que::Job.enqueue :queue => 'other_queue'

    locker = Que::Locker.new

    $q1.pop;      $q1.pop
    $q2.push nil; $q2.push nil

    locker.stop

    DB[:que_jobs].select_map(:queue).should == ['other_queue']
  end

  it "should repeat batch polls on startup until the supply of available jobs is exhausted" do
    100.times { Que::Job.enqueue }
    locker = Que::Locker.new

    sleep_until { DB[:que_jobs].empty? }
    locker.stop
  end

  it "should do batch polls at poll_interval to catch jobs that fall through the cracks" do
    DB[:que_jobs].count.should be 0
    locker = Que::Locker.new :poll_interval => 0.01
    sleep_until { DB[:que_lockers].count == 1 }

    Que::Job.enqueue
    sleep_until { DB[:que_jobs].empty? }

    Que::Job.enqueue
    sleep_until { DB[:que_jobs].empty? }

    locker.stop
  end

  describe "when doing a batch poll" do
    it "should not try to lock and work jobs it has already locked" do
      begin
        $performed = []

        class PollRelockJob < BlockJob
          def run
            $performed << @attrs[:job_id]
            super
          end
        end

        locker = Que::Locker.new :poll_interval => 0.01

        id1 = PollRelockJob.enqueue.attrs[:job_id]
        $q1.pop

        id2 = PollRelockJob.enqueue.attrs[:job_id]
        $q1.pop

        # Without the relock protection, we'd expect the first job to be worked twice.
        $performed.should == [id1, id2]

        $q2.push nil
        $q2.push nil

        locker.stop
      ensure
        $performed = nil
      end
    end

    it "when no named queue is assigned should only work jobs from the default queue" do
      id1 = Que::Job.enqueue.attrs[:job_id]
      id2 = Que::Job.enqueue(:queue => 'my_queue').attrs[:job_id]

      Que::Locker.new.stop

      DB[:que_jobs].select_map(:job_id).should == [id2]
    end

    it "when a named queue is assigned should only work jobs from it" do
      id1 = Que::Job.enqueue.attrs[:job_id]
      id2 = Que::Job.enqueue(:queue => 'my_queue').attrs[:job_id]

      Que::Locker.new(:queue => 'my_queue').stop

      DB[:que_jobs].select_map(:job_id).should == [id1]
    end

    it "should respect a maximum_queue_size setting"

    it "should consider priority settings for workers"

    it "should log what it is doing"
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

    it "should not try to lock and work jobs it has already locked" do
      begin
        $performed = []

        class NotifyRelockJob < BlockJob
          def run
            $performed << @attrs[:job_id]
            super
          end
        end

        attrs = NotifyRelockJob.enqueue.attrs

        locker = Que::Locker.new :listening => true
        $q1.pop

        pid = DB[:que_lockers].where(:listening).get(:pid)

        payload = DB[:que_jobs].
          where(:job_id => attrs[:job_id]).
          select(:queue, :priority, :run_at, :job_id).
          from_self(:alias => :t).
          get{row_to_json(:t)}

        DB.notify "que_locker_#{pid}", :payload => payload

        sleep 0.01 # Hacky

        $q2.push nil
        locker.stop

        locks = DB[:pg_locks].all
      ensure
        $performed = nil
      end
    end

    it "of low importance should not lock them or add them to the JobQueue if it is full"

    it "of significant importance should lock and add them to the JobQueue and dequeue/unlock the least important one to make room"

    it "should log what it is doing"
  end

  describe "when told to shut down" do
    it "should stop all its workers" do
      locker  = Que::Locker.new
      workers = locker.workers
      locker.stop
      workers.each { |worker| worker.thread.status.should be false }
    end

    it "should remove and unlock all the jobs in its queue" do
      6.times { BlockJob.enqueue }
      locker = Que::Locker.new

      job_ids = DB[:que_jobs].select_order_map(:job_id)

      sleep_until { DB[:pg_locks].where(:locktype => 'advisory').select_order_map(:objid) == job_ids }

      4.times { $q1.pop }

      locker.job_queue.to_a.map{|h| h[:job_id].to_i}.should == job_ids[4..5]
      t = Thread.new { locker.stop }

      sleep_until { locker.job_queue.to_a.empty? }
      sleep_until { DB[:pg_locks].where(:locktype => 'advisory').select_order_map(:objid) == job_ids[0..3] }

      4.times { $q2.push nil }
      t.join
    end

    it "should wait for its currently running jobs to finish before returning" do
      locker = Que::Locker.new :listening => true

      job_id = BlockJob.enqueue.attrs[:job_id]

      $q1.pop
      t = Thread.new { locker.stop }
      $q2.push :nil
      t.join

      DB[:que_jobs].should be_empty
    end

    it "should log what it is doing"
  end
end
