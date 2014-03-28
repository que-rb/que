require 'spec_helper'

describe Que::Locker do
  it "should log its settings on startup" do
    Que::Locker.new.stop

    events = logged_messages.select { |m| m['event'] == 'locker_start' }
    events.count.should == 1
    event = events.first
    event['queue'].should == ''
    event['listen'].should == true
    event['backend_pid'].should be_an_instance_of Fixnum
    event['wait_period'].should == 0.01
    event['poll_interval'].should == nil
    event['minimum_queue_size'].should == 2
    event['maximum_queue_size'].should == 8
    event['worker_priorities'].should == [10, 30, 50, nil, nil, nil]
  end

  it "should allow configuration of various parameters" do
    locker = Que::Locker.new :listen             => false,
                             :minimum_queue_size => 5,
                             :maximum_queue_size => 45,
                             :wait_period        => 0.2,
                             :poll_interval      => 0.4,
                             :queue              => 'other_queue',
                             :worker_priorities  => [1, 2, 3, 4],
                             :worker_count       => 8
    locker.stop

    events = logged_messages.select { |m| m['event'] == 'locker_start' }
    events.count.should == 1
    event = events.first
    event['queue'].should == 'other_queue'
    event['listen'].should == false
    event['backend_pid'].should be_an_instance_of Fixnum
    event['wait_period'].should == 0.2
    event['poll_interval'].should == 0.4
    event['minimum_queue_size'].should == 5
    event['maximum_queue_size'].should == 45
    event['worker_priorities'].should == [1, 2, 3, 4, nil, nil, nil, nil]
  end

  it "should allow a dedicated PG connection to be specified" do
    pg = NEW_PG_CONNECTION.call
    pid = pg.async_exec("select pg_backend_pid()").to_a.first['pg_backend_pid'].to_i

    locker = Que::Locker.new :connection => pg

    sleep_until { DB[:que_lockers].select_map(:pid) == [pid] }

    locker.stop
  end

  it "should have a high-priority work thread" do
    locker = Que::Locker.new
    locker.thread.priority.should == 1
    locker.stop
  end

  it "should register its presence or absence in the que_lockers table upon connecting or disconnecting" do
    worker_count = rand(10) + 1

    locker = Que::Locker.new(:worker_count => worker_count)

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
    # connection.
    Que.execute :register_locker, ['', 3, 0, 'blah1', 'true']
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

  it "should do batch polls every poll_interval to catch jobs that fall through the cracks" do
    DB[:que_jobs].count.should be 0
    locker = Que::Locker.new :poll_interval => 0.01, :listen => false

    Que::Job.enqueue
    sleep_until { DB[:que_jobs].empty? }

    Que::Job.enqueue
    sleep_until { DB[:que_jobs].empty? }

    locker.stop
  end

  describe "on startup" do
    it "should do batch polls for jobs" do
      job1, job2 = BlockJob.enqueue, BlockJob.enqueue
      job3       = Que::Job.enqueue :queue => 'other_queue'

      locker = Que::Locker.new

      $q1.pop;      $q1.pop
      $q2.push nil; $q2.push nil

      locker.stop

      DB[:que_jobs].select_map(:queue).should == ['other_queue']
    end

    it "should request enough jobs to fill the queue" do
      ids  = 3.times.map { BlockJob.enqueue(:priority => 100).attrs[:job_id] }
      ids += 6.times.map { Que::Job.enqueue(:priority => 101).attrs[:job_id] }

      locker = Que::Locker.new
      3.times { $q1.pop }

      # The default queue size is 8, so it shouldn't lock the 9th job.
      DB[:pg_locks].where(:locktype => 'advisory').select_order_map(:objid).should == ids[0..-2]

      3.times { $q2.push nil }
      locker.stop
    end

    it "should repeat batch polls until the supply of available jobs is exhausted" do
      Que.execute <<-SQL
        INSERT INTO que_jobs (job_class, priority)
        SELECT 'Que::Job', 1
        FROM generate_series(1, 100) AS i;
      SQL

      locker = Que::Locker.new
      sleep_until { DB[:que_jobs].empty? }
      locker.stop
    end
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

        locker = Que::Locker.new :poll_interval => 0.01, :listen => false

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

      locker = Que::Locker.new

      sleep_until { DB[:que_jobs].select_map(:job_id) == [id2] }
      locker.stop
    end

    it "when a named queue is assigned should only work jobs from it" do
      id1 = Que::Job.enqueue.attrs[:job_id]
      id2 = Que::Job.enqueue(:queue => 'my_queue').attrs[:job_id]

      Que::Locker.new(:queue => 'my_queue').stop

      DB[:que_jobs].select_map(:job_id).should == [id1]
    end

    it "should request as many as necessary to reach the maximum_queue_size" do
      ids  = 3.times.map { BlockJob.enqueue(:priority => 100).attrs[:job_id] }
      ids += 3.times.map { Que::Job.enqueue(:priority => 101).attrs[:job_id] }

      locker = Que::Locker.new :poll_interval => 0.01, :listen => false
      3.times { $q1.pop }

      ids += 6.times.map { Que::Job.enqueue(:priority => 101).attrs[:job_id] }
      sleep_until { DB[:pg_locks].where(:locktype => 'advisory').select_order_map(:objid) == ids[0..10] }

      3.times { $q2.push nil }
      locker.stop

      event = logged_messages.select{|m| m['event'] == 'locker_polled'}.first
      event['queue'].should == ''
      event['limit'].should == 8
      event['locked'].should == 6
    end

    it "should trigger a new batch poll when the queue drops to the minimum_queue_size threshold" do
      ids = 9.times.map { BlockJob.enqueue(:priority => 100).attrs[:job_id] }

      locker = Que::Locker.new
      3.times { $q1.pop }

      # Should have locked first 8 only.
      DB[:pg_locks].where(:locktype => 'advisory').select_order_map(:objid).should == ids[0..7]

      # Get the queue size down to 2, and it should lock the final one.
      6.times { $q2.push nil }
      sleep_until { DB[:pg_locks].where(:locktype => 'advisory').select_map(:objid).include?(ids[-1]) }
      3.times { $q2.push nil }

      locker.stop
    end
  end

  describe "when receiving a NOTIFY of a new job" do
    it "should immediately lock, work, and unlock them" do
      DB[:que_jobs].count.should be 0
      locker = Que::Locker.new
      sleep_until { DB[:que_lockers].count == 1 }

      job = BlockJob.enqueue
      $q1.pop

      locks = DB[:pg_locks].where(:locktype => 'advisory').all
      locks.count.should be 1
      locks.first[:objid].should == DB[:que_jobs].get(:job_id)

      $q2.push nil
      sleep_until { DB[:que_jobs].count == 0 }
      sleep_until { DB[:pg_locks].where(:locktype => 'advisory').count == 0 }

      locker.stop

      events = logged_messages.select { |m| m['event'] == 'job_notified' }
      events.count.should be 1
      event = events.first
      log = event['job']

      log['queue'].should == ''
      log['priority'].should == job.attrs[:priority]
      Time.parse(log['run_at']).should == job.attrs[:run_at]
      log['job_id'].should == job.attrs[:job_id]
    end

    it "should not work jobs that are already locked" do
      DB[:que_jobs].count.should be 0
      locker = Que::Locker.new
      sleep_until { DB[:que_lockers].count == 1 }

      id = nil
      q1, q2 = Queue.new, Queue.new
      t = Thread.new do
        Que.checkout do
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
      t.join

      DB[:que_jobs].select_map(:job_id).should == [id]
    end

    it "should not try to lock and work jobs it has already locked" do
      attrs  = BlockJob.enqueue.attrs
      locker = Que::Locker.new
      $q1.pop

      pid = DB[:que_lockers].where(:listening).get(:pid)

      payload = DB[:que_jobs].
        where(:job_id => attrs[:job_id]).
        select(:queue, :priority, :run_at, :job_id).
        from_self(:alias => :t).
        get{row_to_json(:t)}

      DB.notify "que_locker_#{pid}", :payload => payload

      sleep 0.05 # Hacky
      locker.job_queue.to_a.should == []

      $q2.push nil
      locker.stop
    end

    it "of low importance should not lock them or add them to the JobQueue if it is full" do
      locker = Que::Locker.new :worker_count       => 1,
                               :maximum_queue_size => 3

      sleep_until { DB[:que_lockers].count == 1 }

      BlockJob.enqueue(:priority => 5)
      $q1.pop
      ids = 3.times.map { Que::Job.enqueue(:priority => 5).attrs[:job_id] }
      sleep_until { locker.job_queue.to_a.map{|h| h[-1]} == ids }

      id = Que::Job.enqueue(:priority => 10).attrs[:job_id]

      sleep 0.05 # Hacky.
      locker.job_queue.to_a.map{|h| h[-1]}.should_not include id

      $q2.push nil
      locker.stop
    end

    it "of significant importance should lock and add it to the JobQueue and dequeue/unlock the least important one to make room" do
      locker = Que::Locker.new :worker_count       => 1,
                               :maximum_queue_size => 3

      sleep_until { DB[:que_lockers].count == 1 }

      BlockJob.enqueue :priority => 5
      $q1.pop
      ids = 3.times.map { Que::Job.enqueue(:priority => 5).attrs[:job_id] }

      sleep_until { locker.job_queue.to_a.map{|h| h[-1]} == ids }

      id = Que::Job.enqueue(:priority => 2).attrs[:job_id]

      sleep_until { locker.job_queue.to_a.map{|h| h[-1]} == [id] + ids[0..1] }

      $q2.push nil
      locker.stop
    end
  end

  describe "when told to shut down" do
    it "should stop all its workers" do
      locker  = Que::Locker.new
      workers = locker.workers
      locker.stop
      workers.each { |worker| worker.thread.status.should be false }

      events = logged_messages.select { |m| m['event'] == 'locker_stop' }
      events.count.should be 1
    end

    it "should remove and unlock all the jobs in its queue" do
      6.times { BlockJob.enqueue }
      locker = Que::Locker.new

      job_ids = DB[:que_jobs].select_order_map(:job_id)

      sleep_until { DB[:pg_locks].where(:locktype => 'advisory').select_order_map(:objid) == job_ids }

      3.times { $q1.pop }

      sleep_until { locker.job_queue.to_a.map{|h| h[-1]} == job_ids[3..5] }

      t = Thread.new { locker.stop }

      sleep_until { locker.job_queue.to_a.empty? }
      sleep_until { DB[:pg_locks].where(:locktype => 'advisory').select_order_map(:objid) == job_ids[0..2] }

      3.times { $q2.push nil }

      t.join
    end

    it "should wait for its currently running jobs to finish before returning" do
      locker = Que::Locker.new

      job_id = BlockJob.enqueue.attrs[:job_id]

      $q1.pop
      t = Thread.new { locker.stop }
      $q2.push :nil
      t.join

      DB[:que_jobs].should be_empty
    end
  end
end
