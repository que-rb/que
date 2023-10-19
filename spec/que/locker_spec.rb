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
      sleep_until_equal(1) { DB[:que_lockers].count }

      record = DB[:que_lockers].first
      assert_equal queues,             record[:queues]
      assert_equal Process.pid,        record[:ruby_pid]
      assert_equal Socket.gethostname, record[:ruby_hostname]
      assert_equal listen,             record[:listening]
      assert_equal worker_priorities,  record[:worker_priorities]

      assert_equal worker_priorities, locker.workers.map(&:priority)

      locker.stop!

      assert_equal 0, DB[:que_lockers].count
    end

    it "should have reasonable defaults" do
      assert_que_locker_insertion
    end

    it "should allow configuration of various parameters" do
      locker_settings.merge!(
        queues:              ['my_queue'],
        listen:              false,
        maximum_buffer_size: 45,
        wait_period:         200,
        poll_interval:       0.4,
        worker_priorities:   [1, 2, 3, 4, nil, nil, nil, nil],
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

    it "should allow a different PG connection_url to be specified" do
      locker_settings[:connection_url] = "#{QUE_URL}?application_name=cool-application-name"
      locker

      pid = nil
      sleep_until { pid = DB[:que_lockers].select_map(:pid).first }
      assert_equal 'cool-application-name', DB[:pg_stat_activity].where(pid: pid).get(:application_name)

      locker.stop!
    end

    it "should support an on_worker_start callback" do
      called = 0
      locker_settings[:on_worker_start] = proc { called += 1 }
      locker
      locker.stop!
      assert_equal 6, called
    end

    it "should set an appropriate application_name on the locker's connection" do
      locker

      pid = nil
      sleep_until { pid = DB[:que_lockers].select_map(:pid).first }

      assert_equal(
        DB[:pg_stat_activity].where(pid: pid).get(:application_name),
        "Que Locker: #{pid}",
      )

      locker.stop!
    end

    it "should have a high-priority work thread" do
      sleep_until_equal(1) { locker.thread.priority }

      locker.workers.each do |worker|
        assert locker.thread.priority > worker.thread.priority
      end

      locker.stop!
    end

    it "should clear invalid lockers from the table" do
      # Bogus locker from a nonexistent connection.
      DB[:que_lockers].insert(
        pid:                0,
        ruby_pid:           0,
        ruby_hostname:      'blah2',
        worker_count:       4,
        worker_priorities:  Sequel.pg_array([1, 2, 3, 4], :integer),
        queues:             Sequel.pg_array(['']),
        listening:          true,
        job_schema_version: Que.job_schema_version,
      )

      locker
      sleep_until_equal(0) { DB[:que_lockers].where(pid: 0).count }
      sleep_until_equal(1) { DB[:que_lockers].count }

      record = DB[:que_lockers].first
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

  it "should do batch polls every poll_interval" do
    assert_equal 0, jobs_dataset.count

    locker_settings[:poll_interval] = 0.01
    locker_settings[:poll] = true
    locker_settings[:listen] = false
    locker

    Que::Job.enqueue
    sleep_until { active_jobs_dataset.empty? }

    Que::Job.enqueue
    sleep_until { active_jobs_dataset.empty? }

    locker.stop!
  end

  it "when poll is set to false should still listen for jobs" do
    assert_equal 0, jobs_dataset.count

    locker_settings[:poll] = false
    locker
    sleep_until { !listening_lockers.empty? }

    Que::Job.enqueue
    sleep_until { active_jobs_dataset.empty? }

    Que::Job.enqueue
    sleep_until { active_jobs_dataset.empty? }

    locker.stop!
  end

  describe "with pidfile" do
    it "should create and delete pid file, if not exist" do
      pidfile = "./spec/temp/pidfile_#{Time.new.to_i}.pid"
      locker_settings[:pidfile] = pidfile
      locker
      assert File.exist?(pidfile)

      locker.stop!
      refute File.exist?(pidfile)
    end

    it "should create and delete pid file, if exist" do
      pidfile = "./spec/temp/pidfile_#{Time.new.to_i}.pid"
      File.open(pidfile, "w+") { |f| f.write "test" }

      locker_settings[:pidfile] = pidfile
      locker
      assert File.exist?(pidfile)

      locker.stop!
      refute File.exist?(pidfile)
    end
  end

  describe "on startup" do
    it "should do batch polls for jobs in its specified queue" do
      job1, job2 = BlockJob.enqueue, BlockJob.enqueue
      job3 = Que::Job.enqueue(job_options: { queue: 'my_special_queue' })

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
      job1 = BlockJob.enqueue(job_options: { queue: 'queue1' })
      job2 = BlockJob.enqueue(job_options: { queue: 'queue2' })
      job3 = Que::Job.enqueue(job_options: { queue: 'my_special_queue' })

      locker_settings[:queues] = ['queue1', 'queue2']
      locker
      sleep_until { !listening_lockers.empty? }

      # Two jobs worked simultaneously:
      $q1.pop;      $q1.pop
      $q2.push nil; $q2.push nil

      locker.stop!
      assert_equal(
        [job3.que_attrs[:id]],
        active_jobs_dataset.select_map(:id),
      )
    end

    it "should request only enough jobs to fill the buffer" do
      # Three BlockJobs will tie up the low-priority workers.
      ids  = 3.times.map { BlockJob.enqueue(job_options: { priority: 100 }).que_attrs[:id] }
      ids += 9.times.map { Que::Job.enqueue(job_options: { priority: 101 }).que_attrs[:id] }

      locker
      3.times { $q1.pop }

      # The default buffer size is 8, with 3 open workers, so it shouldn't lock the 12th job.
      assert_equal ids[0..-2], locked_ids

      3.times { $q2.push nil }
      locker.stop!
    end

    it "locks only accepted jobs in a listen batch" do
      locker_settings[:poll] = false
      locker
      sleep_until_equal(1) { DB[:que_lockers].count }

      Que.execute <<~SQL
        INSERT INTO que_jobs (job_class, priority, job_schema_version)
        SELECT 'Que::Job', 1, #{Que.job_schema_version}
        FROM generate_series(1, 10) AS i;
      SQL

      sleep_until_equal(2) { active_jobs_dataset.count }
      sleep_until_equal(0) { locked_ids.size }

      locker.stop!
    end

    it "should repeat batch polls until there are no more available jobs" do
      Que.execute <<-SQL
        INSERT INTO que_jobs (job_class, priority, job_schema_version)
        SELECT 'Que::Job', 1, #{Que.job_schema_version}
        FROM generate_series(1, 100) AS i;
      SQL

      locker_settings[:poll] = true
      locker
      sleep_until(timeout: 10) { active_jobs_dataset.empty? }
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

    it "should request as many as necessary to reach the maximum_buffer_size" do
      # Three BlockJobs to tie up the low-priority workers.
      ids  = 3.times.map { BlockJob.enqueue(job_options: { priority: 100 }).que_attrs[:id] }
      ids += [Que::Job.enqueue(job_options: { priority: 101 }).que_attrs[:id]]

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
            Que::Job.enqueue(job_options: { priority: 101 }).que_attrs[:id]
          end
        end

      sleep_until_equal(ids[0..10]) { locked_ids }

      3.times { $q2.push nil }
      locker.stop!

      locker_polled_events = internal_messages(event: 'poller_polled')

      # First big batch lock, tried to fill the queue and didn't quite get
      # there.
      event = locker_polled_events.shift

      assert_equal 4,  event[:locked]
      assert_equal({:"32767"=>11, :"50"=>1, :"30"=>1, :"10"=>1}, event[:priorities])

      # Second big batch lock, filled the queue.
      second_mass_lock =
        locker_polled_events.find do |e|
          e[:priorities] == {:"32767"=>7, :"50"=>1, :"30"=>1, :"10"=>1} && e[:locked] == 7
        end

      assert(
        second_mass_lock,
        "Didn't find a valid log message in: #{locker_polled_events.inspect}"
      )
    end

    it "should poll in bulk across all the queues it's working" do
      skip

      Que.execute <<-SQL
        INSERT INTO que_jobs (job_class, priority, queue, job_schema_version)
        SELECT 'BlockJob', 60, 'queue_1', #{Que.job_schema_version}
        FROM generate_series(1, 100) AS i;

        INSERT INTO que_jobs (job_class, priority, queue, job_schema_version)
        SELECT 'BlockJob', 10, 'queue_2', #{Que.job_schema_version}
        FROM generate_series(1, 100) AS i;
      SQL

      queue1_jobs = jobs_dataset.where(queue: "queue_1").all
      queue2_jobs = jobs_dataset.where(queue: "queue_2").all

      locker_settings[:queues] = ["queue_1", "queue_2"]
      locker

      sleep_until_equal(11) { locked_ids.length }

      results =
        jobs_dataset.where(id: locked_ids).group_and_count(:queue, :priority).order_by(:queue, :priority).all

      locker.stop

      sleep_until_equal(3) { locked_ids.length }

      3.times { $q1.pop; $q2.push nil }

      locker.stop!
    end

    it "should trigger a new poll when the buffer drops to the minimum size" do
      ids = 12.times.map { BlockJob.enqueue(job_options: { priority: 100 }).que_attrs[:id] }

      locker_settings[:poll] = true
      locker_settings[:poll_interval] = 0.01
      locker
      3.times { $q1.pop }

      # Should have locked first 11 only.
      assert_equal ids[0...11], locked_ids

      # Get the buffer size down to 1, and it should lock the final one.
      9.times { $q2.push nil }
      sleep_until { locked_ids.include?(ids[-1]) }
      3.times { $q2.push nil }

      locker.stop!
    end
  end

  describe "when receiving a NOTIFY of a new job" do
    it "should immediately lock, work, and unlock them" do
      assert_equal 0, jobs_dataset.count

      locker
      sleep_until_equal(1) { DB[:que_lockers].count }

      job = BlockJob.enqueue
      $q1.pop

      assert_equal [job.que_attrs[:id]], locked_ids

      $q2.push nil
      sleep_until_equal(0) { active_jobs_dataset.count }
      sleep_until { locked_ids.empty? }

      locker.stop!
    end

    it "but the job is gone should not leave the lock open" do
      locker
      sleep_until_equal(1) { DB[:que_lockers].count }

      DB.transaction do
        id = jobs_dataset.insert(job_class: "BlockJob", job_schema_version: Que.job_schema_version)
        assert_equal 1, jobs_dataset.where(id: id).delete
      end

      assert_empty jobs_dataset
      locker.stop!
      assert_empty locked_ids
    end

    it "but the job is finished should not leave the lock open" do
      locker
      sleep_until_equal(1) { DB[:que_lockers].count }

      DB.transaction do
        id = jobs_dataset.insert(job_class: "BlockJob", job_schema_version: Que.job_schema_version)
        assert_equal 1, jobs_dataset.where(id: id).update(finished_at: Time.now)
      end

      locker.stop!
      assert_empty locked_ids
    end

    it "but the job is expired should not leave the lock open" do
      locker
      sleep_until_equal(1) { DB[:que_lockers].count }

      DB.transaction do
        id = jobs_dataset.insert(job_class: "BlockJob", job_schema_version: Que.job_schema_version)
        assert_equal 1, jobs_dataset.where(id: id).update(expired_at: Time.now)
      end

      locker.stop!
      assert_empty locked_ids
    end

    it "should receive NOTIFYs for any of the queues it LISTENs for" do
      locker_settings[:queues] = ['queue_1', 'queue_2']
      locker

      sleep_until_equal(1) { DB[:que_lockers].count }
      assert_equal ['queue_1', 'queue_2'], DB[:que_lockers].get(:queues)

      BlockJob.enqueue(job_options: { queue: 'queue_1' })
      BlockJob.enqueue(job_options: { queue: 'queue_2' })

      $q1.pop; $q1.pop

      assert_equal ['queue_1', 'queue_2'], jobs_dataset.select_order_map(:queue)

      $q2.push(nil); $q2.push(nil)

      sleep_until_equal(0) { active_jobs_dataset.count }
      locker.stop!
    end

    it "should not work jobs that are already locked" do
      assert_equal 0, jobs_dataset.count

      # Shouldn't make a difference whether it's polling or not.
      locker_settings[:poll_interval] = 0.01
      locker

      sleep_until_equal(1) { DB[:que_lockers].count }

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
      sleep_until { !listening_lockers.empty? }

      id = BlockJob.enqueue.que_attrs[:id]

      $q1.pop

      assert_equal [], locker.job_buffer.to_a
      assert_equal [id].to_set, locker.locks

      payload =
        jobs_dataset.
          where(id: id).
          select(:queue, :priority, :run_at, :id).first

      payload[:run_at] = payload[:run_at].utc.iso8601(6)

      pid = DB[:que_lockers].get(:pid)
      refute_nil pid
      DB.notify "que_listener_#{pid}",
        payload: JSON.dump(payload.merge(message_type: 'job_available'))

      m = sleep_until { internal_messages(event: 'listener_filtered_messages').first }

      assert_equal(
        [payload.merge(message_type: 'job_available')],
        m[:messages],
      )

      $q2.push nil
      locker.stop!
    end

    it "of low importance should not lock them if the local queue is full" do
      locker_settings.replace(worker_priorities: [10], maximum_buffer_size: 3)
      locker

      sleep_until_equal(1) { DB[:que_lockers].count }

      BlockJob.enqueue(job_options: { priority: 5 })
      $q1.pop
      ids = 3.times.map { Que::Job.enqueue(job_options: { priority: 5 }).que_attrs[:id] }
      sleep_until_equal(ids) { ids_in_local_queue }

      id = Que::Job.enqueue(job_options: { priority: 10 }).que_attrs[:id]

      sleep 0.05 # Hacky.
      refute_includes ids_in_local_queue, id

      $q2.push nil
      locker.stop!
    end

    it "of significant importance should lock and add it to the local queue" do
      locker_settings.replace(worker_priorities: [10], maximum_buffer_size: 3)
      locker

      sleep_until_equal(1) { DB[:que_lockers].count }

      block_job_id = BlockJob.enqueue(job_options: { priority: 5 }).que_attrs[:id]
      $q1.pop
      ids = 3.times.map { Que::Job.enqueue(job_options: { priority: 5 }).que_attrs[:id] }

      sleep_until_equal(ids) { ids_in_local_queue }

      id = Que::Job.enqueue(job_options: { priority: 2 }).que_attrs[:id]

      sleep_until { ids_in_local_queue == [id] + ids[0..1] }
      sleep_until { locked_ids == (ids_in_local_queue + [block_job_id]).sort }

      $q2.push nil
      locker.stop!
    end
  end

  describe "when receiving jobs enqueued with versions of Que which have different job schema versions, it should only lock jobs with a matching job schema version" do
    it "with polling only" do
      locker_settings.clear
      locker_settings.merge!(poll: true, listen: false, poll_interval: 0.01)
      locker
      sleep_until_equal(1) { DB[:que_lockers].count }

      id_other = jobs_dataset.insert(job_class: "BlockJob", job_schema_version: 999_999)
      id_current = jobs_dataset.insert(job_class: "BlockJob", job_schema_version: Que.job_schema_version)

      sleep_until { locked_ids.include?(id_current) }

      refute_includes locked_ids, id_other

      locked_ids.each { $q1.pop; $q2.push nil }
      locker.stop!
    end

    it "with listen only" do
      locker_settings.clear
      locker_settings.merge!(poll: false, listen: true)
      locker
      sleep_until_equal(1) { DB[:que_lockers].count }

      id_other = jobs_dataset.insert(job_class: "BlockJob", job_schema_version: 999_999)
      id_current = jobs_dataset.insert(job_class: "BlockJob", job_schema_version: Que.job_schema_version)

      sleep_until { locked_ids.include?(id_current) }

      refute_includes locked_ids, id_other

      locked_ids.each { $q1.pop; $q2.push nil }
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

      sleep_until_equal(1) do
        workers.count{|w| w.thread.status != false}
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
      job_ids = 6.times.map { BlockJob.enqueue.que_attrs[:id] }
      locker

      sleep_until_equal(job_ids) { locked_ids }

      3.times { $q1.pop }

      sleep_until_equal(job_ids[3..5]) { ids_in_local_queue }

      t = Thread.new { locker.stop! }

      sleep_until { locker.job_buffer.to_a.empty? }
      sleep_until_equal(job_ids[0..2]) { locked_ids }

      3.times { $q2.push nil }

      t.join
    end

    it "should wait for its currently running jobs to finish" do
      locker

      sleep_until_equal(1) { DB[:que_lockers].count }

      job_id = BlockJob.enqueue.que_attrs[:id]

      $q1.pop
      t = Thread.new { locker.stop! }
      $q2.push :nil
      t.join

      assert_equal 0, active_jobs_dataset.count
    end

    it "should clear its own record from the que_lockers table" do
      locker
      sleep_until_equal(1) { DB[:que_lockers].count }

      BlockJob.enqueue
      $q1.pop

      assert_equal 1, DB[:que_lockers].count

      $q2.push nil
      locker.stop!

      assert_equal 0, DB[:que_lockers].count
    end
  end

  describe "when receiving a mix of listened and polled jobs" do
    it "shouldn't execute the same job twice" do
      locker_settings[:poll_interval] = 0.001

      begin
        DB.create_table? :test_data do
          bigint :job_id, primary_key: true
          integer :count
        end

        class QueSpec::RunOnceTestJob < Que::Job
          def run(runs:, index:)
            Que.checkout do |conn|
              conn.execute "BEGIN"
              conn.execute "INSERT INTO test_data (job_id, count) VALUES (#{que_attrs[:id]}, 1) ON CONFLICT (job_id) DO UPDATE SET count = test_data.count + 1"

              if runs < 10
                delay = rand > 0.5 ? 1 : 0
                conn.execute(%(INSERT INTO que_jobs (job_class, kwargs, run_at, job_schema_version) VALUES ('QueSpec::RunOnceTestJob', '{"runs":#{runs + 1},"index":#{index}}', now() + '#{delay} microseconds', #{Que.job_schema_version})))
              end

              finish
              conn.execute "COMMIT"
            end
          end
        end

        lockers = 4.times.map { Que::Locker.new(**locker_settings) }

        5.times { |i| QueSpec::RunOnceTestJob.enqueue(runs: 1, index: i) }

        unless sleep_until? { DB[:test_data].count >= 50 }
          pp DB[:test_data].all
          raise "Jobs weren't completed!"
        end

        lockers.each &:stop!

        assert_equal(
          {
            index_runs: (0..4).flat_map{|i| (1..10).map{|j| [i, j]}},
            job_ids: jobs_dataset.select_order_map(:id),
          },
          {
            index_runs: jobs_dataset.exclude(finished_at: nil).select_map(:kwargs).map{ |a| [a[:index], a[:runs]]}.sort,
            job_ids: DB[:test_data].select_order_map(:job_id),
          }
        )

        assert_empty jobs_dataset.where(finished_at: nil).all
        assert_equal 50, jobs_dataset.count

        assert_equal 50, DB[:test_data].count
        assert_equal 50, DB[:test_data].where(count: 1).count
      ensure
        DB.drop_table :test_data
      end
    end
  end
end
