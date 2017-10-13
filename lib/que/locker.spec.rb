# frozen_string_literal: true

require 'spec_helper'

describe Que::Locker do
  describe "when starting up" do
    def assert_que_locker_insertion(
      listen:             true,
      queues:             [Que::DEFAULT_QUEUE],
      worker_priorities:  [10, 30, 50, nil, nil, nil]
    )

      assert_equal 0, DB[:que_lockers].count
      locker
      sleep_until! { DB[:que_lockers].count == 1 }

      record = DB[:que_lockers].first
      assert_equal queues,                   record[:queues]
      assert_equal Process.pid,              record[:ruby_pid]
      assert_equal Socket.gethostname,       record[:ruby_hostname]
      assert_equal worker_priorities.length, record[:worker_count]
      assert_equal listen,                   record[:listening]
      assert_equal worker_priorities,        record[:worker_priorities]

      assert_equal worker_priorities, locker.workers.map(&:priority)

      locker.stop!

      assert_equal 0, DB[:que_lockers].count
    end

    it "should have reasonable defaults" do
      assert_que_locker_insertion
    end

    it "should allow configuration of various parameters" do
      locker_settings.merge!(
        queues:             ['my_queue'],
        listen:             false,
        minimum_queue_size: 5,
        maximum_queue_size: 45,
        wait_period:        200,
        poll_interval:      0.4,
        worker_priorities:  [1, 2, 3, 4],
        worker_count:       8,
      )

      assert_que_locker_insertion(
        queues:             ['my_queue'],
        listen:             false,
        worker_priorities:  [1, 2, 3, 4, nil, nil, nil, nil],
      )
    end

    it "should respect the Que.default_queue configuration option" do
      begin
        Que.default_queue = 'a_new_default_queue'
        locker_settings.clear

        assert_que_locker_insertion(
          queues: ['a_new_default_queue'],
        )
      ensure
        Que.default_queue = nil
        assert_equal 'default', Que.default_queue
      end
    end

    it "should allow a dedicated PG connection to be specified" do
      pg = EXTRA_PG_CONNECTION

      locker_settings[:connection] = pg
      locker

      sleep_until! { DB[:que_lockers].select_map(:pid) == [pg.backend_pid] }
      locker.stop!
    end

    it "should support an on_worker_start callback" do
      called = 0
      locker_settings[:on_worker_start] = proc { called += 1 }
      locker
      locker.stop!
      assert_equal 6, called
    end

    it "should set the application_name while the locker has the connection" do
      pg = EXTRA_PG_CONNECTION

      original_application_name = pg.async_exec("SHOW application_name").to_a.first["application_name"]

      locker_settings[:connection] = pg
      locker

      sleep_until! { DB[:que_lockers].select_map(:pid) == [pg.backend_pid] }

      assert_equal(
        DB[:pg_stat_activity].where(pid: pg.backend_pid).get(:application_name),
        "Que Locker: #{pg.backend_pid}",
      )

      locker.stop!

      assert_equal(
        DB[:pg_stat_activity].where(pid: pg.backend_pid).get(:application_name),
        original_application_name,
      )
    end

    it "should have a high-priority work thread" do
      sleep_until! { locker.thread.priority == 1 }

      locker.workers.each do |worker|
        assert locker.thread.priority > worker.thread.priority
      end

      locker.stop!
    end

    it "should clear invalid lockers from the table" do
      # Bogus locker from a nonexistent connection.
      DB[:que_lockers].insert(
        pid:               0,
        ruby_pid:          0,
        ruby_hostname:     'blah2',
        worker_count:      4,
        worker_priorities: Sequel.pg_array([1, 2, 3, 4], :integer),
        queues:            Sequel.pg_array(['']),
        listening:         true,
      )

      Que.checkout do |conn|
        # We want to spec that invalid lockers with the current backend's pid are
        # also cleared out, so:
        backend_pid =
          Que.execute("select pg_backend_pid()").first[:pg_backend_pid]

        DB[:que_lockers].insert(
          pid:               backend_pid,
          ruby_pid:          0,
          ruby_hostname:     'blah1',
          worker_count:      4,
          worker_priorities: Sequel.pg_array([1, 2, 3, 4], :integer),
          queues:            Sequel.pg_array(['']),
          listening:         true,
        )

        assert_equal 2, DB[:que_lockers].count

        locker_settings[:connection] = conn
        locker
        sleep_until! { DB[:que_lockers].count == 1 }

        record = DB[:que_lockers].first
        assert_equal backend_pid, record[:pid]
        assert_equal Process.pid, record[:ruby_pid]

        locker.stop!

        assert_equal 0, DB[:que_lockers].count
      end
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

  it "should do batch polls every poll_interval" do
    assert_equal 0, jobs_dataset.count

    locker_settings[:poll_interval] = 0.01
    locker_settings[:poll] = true
    locker_settings[:listen] = false
    locker

    Que::Job.enqueue
    sleep_until! { active_jobs_dataset.empty? }

    Que::Job.enqueue
    sleep_until! { active_jobs_dataset.empty? }

    locker.stop!
  end

  it "when poll is set to false should still listen for jobs" do
    assert_equal 0, jobs_dataset.count

    locker_settings[:poll] = false
    locker
    sleep_until! { !listening_lockers.empty? }

    Que::Job.enqueue
    sleep_until! { active_jobs_dataset.empty? }

    Que::Job.enqueue
    sleep_until! { active_jobs_dataset.empty? }

    locker.stop!
  end

  describe "on startup" do
    it "should do batch polls for jobs in its specified queue" do
      job1, job2 = BlockJob.enqueue, BlockJob.enqueue
      job3 = Que::Job.enqueue(queue: 'my_special_queue')

      locker_settings[:poll] = true
      locker

      # Two jobs worked simultaneously:
      $q1.pop;      $q1.pop
      $q2.push nil; $q2.push nil

      locker.stop!
      assert_equal(
        [job3.que_attrs[:id]],
        active_jobs_dataset.select_map(:id),
      )
    end

    it "should do batch polls for jobs in its specified queues" do
      job1 = BlockJob.enqueue(queue: 'queue1')
      job2 = BlockJob.enqueue(queue: 'queue2')
      job3 = Que::Job.enqueue(queue: 'my_special_queue')

      locker_settings[:queues] = ['queue1', 'queue2']
      locker
      sleep_until! { !listening_lockers.empty? }

      # Two jobs worked simultaneously:
      $q1.pop;      $q1.pop
      $q2.push nil; $q2.push nil

      locker.stop!
      assert_equal(
        [job3.que_attrs[:id]],
        active_jobs_dataset.select_map(:id),
      )
    end

    it "should request only enough jobs to fill the queue" do
      skip

      # Three BlockJobs will tie up the low-priority workers.
      ids  = 3.times.map { BlockJob.enqueue(priority: 100).que_attrs[:id] }
      ids += 9.times.map { Que::Job.enqueue(priority: 101).que_attrs[:id] }

      locker
      3.times { $q1.pop }

      # The default queue size is 8, with 3 open workers, so it shouldn't lock the 12th job.
      assert_equal ids[0..-2], locked_ids

      3.times { $q2.push nil }
      locker.stop!
    end

    it "should repeat batch polls until there are no more available jobs" do
      Que.execute <<-SQL
        INSERT INTO que_jobs (job_class, priority)
        SELECT 'Que::Job', 1
        FROM generate_series(1, 100) AS i;
      SQL

      locker_settings[:poll] = true
      locker
      sleep_until!(10) { active_jobs_dataset.empty? }
      locker.stop!
    end
  end

  describe "when doing a batch poll" do
    it "should not try to lock and work jobs it has already locked" do
      begin
        $performed = []

        class PollRelockJob < BlockJob
          def run
            $performed << que_attrs[:id]
            super
          end
        end

        locker_settings.clear
        locker_settings[:poll_interval] = 0.01
        locker_settings[:listen] = false
        locker

        id1 = PollRelockJob.enqueue.que_attrs[:id]
        $q1.pop

        id2 = PollRelockJob.enqueue.que_attrs[:id]
        $q1.pop

        # Without the relock protection, we'd expect the first job to be worked
        # twice.
        assert_equal [id1, id2], $performed

        $q2.push nil
        $q2.push nil

        locker.stop!
      ensure
        $performed = nil
      end
    end

    it "should request as many as necessary to reach the maximum_queue_size" do
      skip

      # Three BlockJobs to tie up the low-priority workers.
      ids  = 3.times.map { BlockJob.enqueue(priority: 100).que_attrs[:id] }
      ids += [Que::Job.enqueue(priority: 101).que_attrs[:id]]

      locker_settings.clear
      locker_settings[:poll_interval] = 0.01
      locker_settings[:listen] = false
      locker

      3.times { $q1.pop }
      assert_equal ids, locked_ids

      # Use a transaction to make sure that the locker is able to see all of
      # these jobs at the same time.
      ids +=
        Que.transaction do
          8.times.map do
            Que::Job.enqueue(priority: 101).que_attrs[:id]
          end
        end

      sleep_until! { locked_ids == ids[0..10] }

      3.times { $q2.push nil }
      locker.stop!

      locker_polled_events = internal_messages(event: 'poller_polled')

      # First big batch lock, tried to fill the queue and didn't quite get
      # there.
      event = locker_polled_events.shift
      assert_equal 11, event[:limit]
      assert_equal 4,  event[:locked]

      # Second big batch lock, filled the queue.
      second_mass_lock =
        locker_polled_events.find do |e|
          e[:limit] == 7 && e[:locked] == 7
        end

      assert(
        second_mass_lock,
        "Didn't find a valid log message in: #{locker_polled_events.inspect}"
      )
    end

    it "should trigger a new poll when the queue drops to the minimum size" do
      skip

      ids = 12.times.map { BlockJob.enqueue(priority: 100).que_attrs[:id] }

      locker_settings[:poll] = true
      locker
      3.times { $q1.pop }

      # Should have locked first 11 only.
      assert_equal ids[0...11], locked_ids

      # Get the queue size down to 1, and it should lock the final one.
      9.times { $q2.push nil }
      sleep_until! { locked_ids.include?(ids[-1]) }
      3.times { $q2.push nil }

      locker.stop!
    end
  end

  describe "when receiving a NOTIFY of a new job" do
    it "should immediately lock, work, and unlock them" do
      assert_equal 0, jobs_dataset.count

      locker
      sleep_until! { DB[:que_lockers].count == 1 }

      job = BlockJob.enqueue
      $q1.pop

      assert_equal [job.que_attrs[:id]], locked_ids

      $q2.push nil
      sleep_until! { active_jobs_dataset.count == 0 }
      sleep_until! { locked_ids.empty? }

      locker.stop!
    end

    it "should receive NOTIFYs for any of the queues it LISTENs for" do
      locker_settings[:queues] = ['queue_1', 'queue_2']
      locker

      sleep_until! { DB[:que_lockers].count == 1 }
      assert_equal ['queue_1', 'queue_2'], DB[:que_lockers].get(:queues)

      BlockJob.enqueue queue: 'queue_1'
      BlockJob.enqueue queue: 'queue_2'

      $q1.pop; $q1.pop

      assert_equal ['queue_1', 'queue_2'], jobs_dataset.select_order_map(:queue)

      $q2.push(nil); $q2.push(nil)

      sleep_until! { active_jobs_dataset.count == 0 }
      locker.stop!
    end

    it "should not work jobs that are already locked" do
      assert_equal 0, jobs_dataset.count

      # Shouldn't make a difference whether it's polling or not.
      locker_settings[:poll_interval] = 0.01
      locker

      sleep_until! { DB[:que_lockers].count == 1 }

      id = nil
      q1, q2 = Queue.new, Queue.new
      t =
        Thread.new do
          Que.checkout do
            # NOTIFY won't propagate until transaction commits.
            Que.execute "BEGIN"
            id = Que::Job.enqueue.que_attrs[:id]
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

      assert_equal [id], active_jobs_dataset.select_map(:id)
    end

    it "should not try to lock and work jobs it has already locked" do
      locker
      sleep_until! { !listening_lockers.empty? }

      id = BlockJob.enqueue.que_attrs[:id]

      $q1.pop

      assert_equal [], locker.job_cache.to_a
      assert_equal [id].to_set, locker.locks

      payload =
        jobs_dataset.
          where(id: id).
          select(:queue, :priority, :run_at, :id).first

      payload[:run_at] = payload[:run_at].utc.iso8601(6)

      pid = DB[:que_lockers].get(:pid)
      refute_nil pid
      DB.notify "que_listener_#{pid}",
        payload: JSON.dump(payload.merge(message_type: 'work_job'))

      m = sleep_until! { internal_messages(event: 'listener_filtered_messages').first }

      assert_equal(
        [payload.merge(message_type: 'work_job')],
        m[:messages],
      )

      $q2.push nil
      locker.stop!
    end

    it "of low importance should not lock them if the local queue is full" do
      locker_settings.replace(worker_count: 1, maximum_queue_size: 3)
      locker

      sleep_until! { DB[:que_lockers].count == 1 }

      BlockJob.enqueue(priority: 5)
      $q1.pop
      ids = 3.times.map { Que::Job.enqueue(priority: 5).que_attrs[:id] }
      sleep_until! { ids_in_local_queue == ids }

      id = Que::Job.enqueue(priority: 10).que_attrs[:id]

      sleep 0.05 # Hacky.
      refute_includes ids_in_local_queue, id

      $q2.push nil
      locker.stop!
    end

    it "of significant importance should lock and add it to the local queue" do
      locker_settings.replace(worker_count: 1, maximum_queue_size: 3)
      locker

      sleep_until! { DB[:que_lockers].count == 1 }

      block_job_id = BlockJob.enqueue(priority: 5).que_attrs[:id]
      $q1.pop
      ids = 3.times.map { Que::Job.enqueue(priority: 5).que_attrs[:id] }

      sleep_until! { ids_in_local_queue == ids }

      id = Que::Job.enqueue(priority: 2).que_attrs[:id]

      sleep_until! { ids_in_local_queue == [id] + ids[0..1] }
      sleep_until! { locked_ids == (ids_in_local_queue + [block_job_id]).sort }

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

      sleep_until! do
        workers.count{|w| w.thread.status != false} == 1
      end

      $q2.push nil

      assert locker.stopping?

      locker.wait_for_stop
      workers.each { |worker| assert_equal false, worker.thread.status }
    end

    it "with #stop! should block until its workers are done" do
      workers = locker.workers
      locker.stop!
      workers.each { |worker| assert_equal false, worker.thread.status }

      events = logged_messages.select { |m| m[:event] == 'locker_stop' }
      assert_equal 1, events.count
    end

    it "should remove and unlock all the jobs in its queue" do
      skip

      job_ids = 6.times.map { BlockJob.enqueue.que_attrs[:id] }
      locker

      sleep_until! { locked_ids == job_ids }

      3.times { $q1.pop }

      sleep_until! { ids_in_local_queue == job_ids[3..5] }

      t = Thread.new { locker.stop! }

      sleep_until! { locker.job_cache.to_a.empty? }
      sleep_until! { locked_ids == job_ids[0..2] }

      3.times { $q2.push nil }

      t.join
    end

    it "should wait for its currently running jobs to finish" do
      locker

      sleep_until! { DB[:que_lockers].count == 1 }

      job_id = BlockJob.enqueue.que_attrs[:id]

      $q1.pop
      t = Thread.new { locker.stop! }
      $q2.push :nil
      t.join

      assert_equal 0, active_jobs_dataset.count
    end

    it "should clear its own record from the que_lockers table" do
      locker
      sleep_until! { DB[:que_lockers].count == 1 }

      BlockJob.enqueue
      $q1.pop

      assert_equal 1, DB[:que_lockers].count

      $q2.push nil
      locker.stop!

      assert_equal 0, DB[:que_lockers].count
    end
  end
end
