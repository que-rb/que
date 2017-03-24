# frozen_string_literal: true

require 'spec_helper'

describe Que::Locker do
  describe "when starting up" do
    it "should log its settings" do
      locker_settings.clear
      locker.stop!

      events = logged_messages.select { |m| m['event'] == 'locker_start' }
      assert_equal 1, events.count

      event = events.first
      assert_equal true,         event['listen']
      assert_instance_of Fixnum, event['backend_pid']

      assert_equal Que::Locker::DEFAULT_POLL_INTERVAL,      event['poll_interval']
      assert_equal Que::Locker::DEFAULT_WAIT_PERIOD,        event['wait_period']
      assert_equal Que::Locker::DEFAULT_MINIMUM_QUEUE_SIZE, event['minimum_queue_size']
      assert_equal Que::Locker::DEFAULT_MAXIMUM_QUEUE_SIZE, event['maximum_queue_size']
      assert_equal Que::Locker::DEFAULT_WORKER_COUNT,       event['worker_priorities'].count

      # If the worker_count is six and the worker_priorities are [10, 30, 50], the
      # expected full set of worker priorities is [10, 30, 50, nil, nil, nil].

      expected_worker_priorities =
        Que::Locker::DEFAULT_WORKER_PRIORITIES +
        (
          Que::Locker::DEFAULT_WORKER_COUNT -
          Que::Locker::DEFAULT_WORKER_PRIORITIES.length
        ).times.map { nil }

      assert_equal expected_worker_priorities, event['worker_priorities']
    end

    it "should allow configuration of various parameters" do
      locker_settings.merge!(
        listen:             false,
        minimum_queue_size: 5,
        maximum_queue_size: 45,
        wait_period:        0.2,
        poll_interval:      0.4,
        worker_priorities:  [1, 2, 3, 4],
        worker_count:       8,
      )

      locker.stop!

      events = logged_messages.select { |m| m['event'] == 'locker_start' }
      assert_equal 1, events.count
      event = events.first
      assert_equal false, event['listen']
      assert_instance_of Fixnum, event['backend_pid']
      assert_equal 0.2, event['wait_period']
      assert_equal 0.4, event['poll_interval']
      assert_equal 5, event['minimum_queue_size']
      assert_equal 45, event['maximum_queue_size']
      assert_equal [1, 2, 3, 4, nil, nil, nil, nil], event['worker_priorities']
    end

    it "should allow a dedicated PG connection to be specified" do
      pg = NEW_PG_CONNECTION.call
      pid = backend_pid(pg)

      locker_settings[:connection] = pg
      locker

      sleep_until { DB[:que_lockers].select_map(:pid) == [pid] }
      locker.stop!
    end

    it "should have a high-priority work thread" do
      assert_equal 1, locker.thread.priority
      locker.stop!
    end

    it "should register its presence in the que_lockers table" do
      worker_count = rand(10) + 1
      locker_settings[:worker_count] = worker_count

      locker
      sleep_until { DB[:que_lockers].count == 1 }

      assert_equal worker_count, locker.workers.count

      record = DB[:que_lockers].first
      assert_equal Process.pid,        record[:ruby_pid]
      assert_equal Socket.gethostname, record[:ruby_hostname]
      assert_equal worker_count,       record[:worker_count]
      assert_equal true,               record[:listening]

      locker.stop!

      assert_equal 0, DB[:que_lockers].count
    end

    it "should clear invalid lockers from the table" do
      # Bogus locker from a nonexistent connection.
      DB[:que_lockers].insert(
        pid:           0,
        ruby_pid:      0,
        ruby_hostname: 'blah2',
        worker_count:  4,
        listening:     true,
      )

      # We want to spec that invalid lockers with the current backend's pid are
      # also cleared out, so:
      backend_pid =
        Que.execute("select pg_backend_pid()").first[:pg_backend_pid]

      DB[:que_lockers].insert(
        pid:           backend_pid,
        ruby_pid:      0,
        ruby_hostname: 'blah1',
        worker_count:  4,
        listening:     true,
      )

      assert_equal 2, DB[:que_lockers].count

      locker
      sleep_until { DB[:que_lockers].count == 1 }

      record = DB[:que_lockers].first
      assert_equal backend_pid, record[:pid]
      assert_equal Process.pid, record[:ruby_pid]

      locker.stop!

      assert_equal 0, DB[:que_lockers].count
    end

    it "should run the on_worker_start callback for each worker, if passed" do
      a = []
      m = Mutex.new

      locker_settings[:on_worker_start] =
        proc do |worker|
          m.synchronize do
            a << [worker.object_id, Thread.current.object_id]
          end
        end

      locker

      ids = locker.workers.map{|w| [w.object_id, w.thread.object_id]}

      locker.stop!

      assert_equal ids.sort, a.sort
    end
  end

  it "should do batch polls every poll_interval to catch jobs that fall through the cracks" do
    assert_equal 0, DB[:que_jobs].count

    locker_settings[:poll_interval] = 0.01
    locker_settings[:listen] = false
    locker

    Que::Job.enqueue
    sleep_until { DB[:que_jobs].empty? }

    Que::Job.enqueue
    sleep_until { DB[:que_jobs].empty? }

    locker.stop!
  end

  it "when poll_interval is set to nil should still listen for jobs" do
    assert_equal 0, DB[:que_jobs].count

    locker_settings[:poll_interval] = nil
    sleep_until { locker.thread.status == 'sleep' }

    Que::Job.enqueue
    sleep_until { DB[:que_jobs].empty? }

    Que::Job.enqueue
    sleep_until { DB[:que_jobs].empty? }

    locker.stop!
  end

  describe "on startup" do
    it "should do batch polls for jobs" do
      job1, job2 = BlockJob.enqueue, BlockJob.enqueue

      locker

      # Two jobs worked simultaneously:
      $q1.pop;      $q1.pop
      $q2.push nil; $q2.push nil

      locker.stop!
      assert_equal 0, DB[:que_jobs].count
    end

    it "should request enough jobs to fill the queue" do
      # Three BlockJobs will tie up the low-priority workers.
      ids  = 3.times.map { BlockJob.enqueue(priority: 100).attrs[:job_id] }
      ids += 6.times.map { Que::Job.enqueue(priority: 101).attrs[:job_id] }

      locker
      3.times { $q1.pop }

      # The default queue size is 8, so it shouldn't lock the 9th job.
      assert_equal ids[0..-2], locked_ids

      3.times { $q2.push nil }
      locker.stop!
    end

    it "should repeat batch polls until the supply of available jobs is exhausted" do
      Que.execute <<-SQL
        INSERT INTO que_jobs (job_class, priority)
        SELECT 'Que::Job', 1
        FROM generate_series(1, 100) AS i;
      SQL

      locker_settings.clear
      locker
      sleep_until { DB[:que_jobs].empty? }
      locker.stop!
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

        locker_settings.clear
        locker_settings[:poll_interval] = 0.01
        locker_settings[:listen] = false
        locker

        id1 = PollRelockJob.enqueue.attrs[:job_id]
        $q1.pop

        id2 = PollRelockJob.enqueue.attrs[:job_id]
        $q1.pop

        # Without the relock protection, we'd expect the first job to be worked twice.
        assert_equal [id1, id2], $performed

        $q2.push nil
        $q2.push nil

        locker.stop!
      ensure
        $performed = nil
      end
    end

    it "should request as many as necessary to reach the maximum_queue_size" do
      # Three BlockJobs to tie up the low-priority workers.
      ids  = 3.times.map { BlockJob.enqueue(priority: 100).attrs[:job_id] }
      ids += 3.times.map { Que::Job.enqueue(priority: 101).attrs[:job_id] }

      locker_settings.clear
      locker_settings[:poll_interval] = 0.01
      locker_settings[:listen] = false
      locker
      3.times { $q1.pop }

      # Use a transaction to make sure that the locker is able to see all of
      # these jobs at the same time.
      ids +=
        Que.transaction do
          6.times.map do
            Que::Job.enqueue(priority: 101).attrs[:job_id]
          end
        end

      sleep_until { locked_ids == ids[0..10] }

      3.times { $q2.push nil }
      locker.stop!

      locker_polled_events =
        logged_messages.select{|m| m['event'] == 'locker_polled'}

      # First big batch lock, tried to fill the queue and didn't quite get
      # there.
      event = locker_polled_events.shift
      assert_equal 8, event['limit']
      assert_equal 6, event['locked']

      # Second big batch lock, filled the queue.
      second_mass_lock =
        locker_polled_events.find do |e|
          e['limit'] == 5 && e['locked'] == 5
        end

      assert(second_mass_lock, "Didn't find a valid log message in: #{locker_polled_events.inspect}")
    end

    it "should trigger a new batch poll when the queue drops to the minimum_queue_size threshold" do
      ids = 9.times.map { BlockJob.enqueue(priority: 100).attrs[:job_id] }

      locker
      3.times { $q1.pop }

      # Should have locked first 8 only.
      assert_equal ids[0..7], locked_ids

      # Get the queue size down to 2, and it should lock the final one.
      6.times { $q2.push nil }
      sleep_until { locked_ids.include?(ids[-1]) }
      3.times { $q2.push nil }

      locker.stop!
    end
  end

  describe "when receiving a NOTIFY of a new job" do
    it "should immediately lock, work, and unlock them" do
      assert_equal 0, DB[:que_jobs].count

      locker
      sleep_until { DB[:que_lockers].count == 1 }

      job = BlockJob.enqueue
      $q1.pop

      assert_equal [job.attrs[:job_id]], locked_ids

      $q2.push nil
      sleep_until { DB[:que_jobs].count == 0 }
      sleep_until { locked_ids.empty? }

      locker.stop!

      events = logged_messages.select { |m| m['event'] == 'job_notified' }
      assert_equal 1, events.count
      event = events.first
      log = event['job']

      assert_equal job.attrs[:priority], log['priority']
      assert_equal job.attrs[:run_at],   Time.parse(log['run_at'])
      assert_equal job.attrs[:job_id],   log['job_id']
    end

    it "should not work jobs that are already locked" do
      assert_equal 0, DB[:que_jobs].count

      # Shouldn't make a difference whether it's polling or not.
      locker_settings[:poll_interval] = 0.01
      locker

      sleep_until { DB[:que_lockers].count == 1 }

      id = nil
      q1, q2 = Queue.new, Queue.new
      t =
        Thread.new do
          Que.checkout do
            # NOTIFY won't propagate until transaction commits.
            Que.execute "BEGIN"
            id = Que::Job.enqueue.attrs[:job_id]
            Que.execute "SELECT pg_advisory_lock($1)", [id]
            Que.execute "COMMIT"
            q1.push nil
            q2.pop
            Que.execute "SELECT pg_advisory_unlock($1)", [id]
          end
        end

      q1.pop
      locker.stop!
      q2.push nil
      t.join

      assert_equal [id], DB[:que_jobs].select_map(:job_id)
    end

    it "should not try to lock and work jobs it has already locked" do
      id = BlockJob.enqueue.attrs[:job_id]
      locker
      $q1.pop

      assert_equal [], locker.job_queue.to_a
      assert_equal [id].to_set, locker.locks

      message_count = logged_messages.count

      payload =
        DB[:que_jobs].
          where(job_id: id).
          select(:priority, :run_at, :job_id).
          from_self(alias: :t).
          get{row_to_json(:t)}

      pid = locker.backend_pid
      refute_nil pid
      DB.notify "que_locker_#{pid}", payload: payload

      # A bit hacky. Nothing should happen in response to this payload, so wait
      # a bit and then assert that nothing happened.
      sleep 0.05

      messages = logged_messages
      messages.shift(message_count)

      # Use messages to check that the NOTIFY was received, but no action was
      # taken.
      assert_equal 1, messages.length
      message = messages.first
      assert_equal 'job_notified', message['event']
      assert_equal payload, JSON.dump(message['job'])

      $q2.push nil
      locker.stop!
    end

    it "of low importance should not lock them or add them to the JobQueue if it is full" do
      locker_settings.replace(worker_count: 1, maximum_queue_size: 3)
      locker

      sleep_until { DB[:que_lockers].count == 1 }

      BlockJob.enqueue(priority: 5)
      $q1.pop
      ids = 3.times.map { Que::Job.enqueue(priority: 5).attrs[:job_id] }
      sleep_until { ids_in_local_queue == ids }

      id = Que::Job.enqueue(priority: 10).attrs[:job_id]

      sleep 0.05 # Hacky.
      refute_includes ids_in_local_queue, id

      $q2.push nil
      locker.stop!
    end

    it "of significant importance should lock and add it to the JobQueue and dequeue/unlock the least important one to make room" do
      locker_settings.replace(worker_count: 1, maximum_queue_size: 3)
      locker

      sleep_until { DB[:que_lockers].count == 1 }

      block_job_id = BlockJob.enqueue(priority: 5).attrs[:job_id]
      $q1.pop
      ids = 3.times.map { Que::Job.enqueue(priority: 5).attrs[:job_id] }

      sleep_until { ids_in_local_queue == ids }

      id = Que::Job.enqueue(priority: 2).attrs[:job_id]

      sleep_until { ids_in_local_queue == [id] + ids[0..1] }
      sleep_until { locked_ids == (ids_in_local_queue + [block_job_id]).sort }

      $q2.push nil
      locker.stop!
    end
  end

  describe "when told to shut down" do
    it "with #stop should inform its workers to stop" do
      BlockJob.enqueue
      locker
      $q1.pop

      workers = locker.workers
      locker.stop

      sleep_until do
        workers.count{|w| w.thread.status != false} == 1
      end

      $q2.push nil

      locker.wait_for_stop
      workers.each { |worker| assert_equal false, worker.thread.status }
    end

    it "with #stop! should block until its workers are done" do
      workers = locker.workers
      locker.stop!
      workers.each { |worker| assert_equal false, worker.thread.status }

      events = logged_messages.select { |m| m['event'] == 'locker_stop' }
      assert_equal 1, events.count
    end

    it "should remove and unlock all the jobs in its queue" do
      job_ids = 6.times.map { BlockJob.enqueue.attrs[:job_id] }
      locker

      sleep_until { locked_ids == job_ids }

      3.times { $q1.pop }

      sleep_until { ids_in_local_queue == job_ids[3..5] }

      t = Thread.new { locker.stop! }

      sleep_until { locker.job_queue.to_a.empty? }
      sleep_until { locked_ids == job_ids[0..2] }

      3.times { $q2.push nil }

      t.join
    end

    it "should wait for its currently running jobs to finish before returning" do
      locker

      sleep_until { DB[:que_lockers].count == 1 }

      job_id = BlockJob.enqueue.attrs[:job_id]

      $q1.pop
      t = Thread.new { locker.stop! }
      $q2.push :nil
      t.join

      assert_equal 0, DB[:que_jobs].count
    end

    it "should clear its own record from the que_lockers table"
  end
end
