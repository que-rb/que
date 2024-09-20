# frozen_string_literal: true

require 'spec_helper'

describe Que::Poller do
  let :connection do
    Que::Connection.wrap(EXTRA_PG_CONNECTION)
  end

  def held_advisory_locks(override_connection: nil)
    ids =
      (override_connection || connection).execute <<-SQL
        SELECT ((classid::bigint << 32) + objid::bigint) AS id
        FROM pg_locks
        WHERE locktype = 'advisory'
        AND pid = pg_backend_pid()
      SQL

    ids.map!{|h| h[:id].to_i}.sort
  end

  let :default_priorities do
    {
      10    => 1,
      30    => 1,
      50    => 1,
      32767 => 3,
    }
  end

  def poll(
    priorities: default_priorities,
    queue_name: 'default',
    job_ids: [],
    override_connection: nil
  )

    assert_empty held_advisory_locks(override_connection: override_connection)

    job_ids = job_ids.to_set

    poller =
      Que::Poller.new(
        connection: override_connection || connection,
        queue: queue_name,
        poll_interval: 5,
        poll_interval_variance: 0,
      )

    Que::Poller.setup(override_connection || connection)
    metajobs = poller.poll(priorities: priorities, held_locks: job_ids)
    Que::Poller.cleanup(override_connection || connection)

    metajobs.each do |metajob|
      # Make sure we pull in run_at timestamps in iso8601 format.
      assert_match(Que::TIME_REGEX, metajob.job[:run_at])
    end

    returned_job_ids = metajobs.map(&:id)

    assert_equal held_advisory_locks(override_connection: override_connection), returned_job_ids.sort

    returned_job_ids
  end

  after do
    connection.execute "SELECT pg_advisory_unlock_all()"
  end

  it "should not fail if there aren't enough jobs to return" do
    id = Que::Job.enqueue.que_attrs[:id]
    assert_equal [id], poll
  end

  it "should not fail if the jobs table is empty" do
    assert_equal [], poll
  end

  it "should return only the requested number of jobs" do
    ids = 5.times.map { Que::Job.enqueue.que_attrs[:id] }
    assert_equal ids[0..3], poll(priorities: {200 => 4})
  end

  it "should skip jobs with the given ids" do
    one, two = 2.times.map { Que::Job.enqueue.que_attrs[:id] }

    assert_equal [two], poll(job_ids: [one])
  end

  it "should skip jobs in the wrong queue" do
    one = Que::Job.enqueue(job_options: { queue: 'one' }).que_attrs[:id]
    two = Que::Job.enqueue(job_options: { queue: 'two' }).que_attrs[:id]

    assert_equal [one], poll(queue_name: 'one')
  end

  it "should skip jobs that are finished" do
    one = Que::Job.enqueue.que_attrs[:id]
    two = Que::Job.enqueue.que_attrs[:id]

    jobs_dataset.where(id: two).update(finished_at: Time.now)

    assert_equal [one], poll
  end

  it "should skip jobs that are expired" do
    one = Que::Job.enqueue.que_attrs[:id]
    two = Que::Job.enqueue.que_attrs[:id]

    jobs_dataset.where(id: two).update(expired_at: Time.now)

    assert_equal [one], poll
  end

  it "should skip jobs that don't meet the priority requirements" do
    one = Que::Job.enqueue(job_options: { priority: 7 }).que_attrs[:id]
    two = Que::Job.enqueue(job_options: { priority: 8 }).que_attrs[:id]

    assert_equal [one], poll(priorities: {7 => 5})
  end

  describe "when passed a set of priority requirements" do
    before do
      priorities = []
      [10, 20, 30, 40, 50].each {|p| priorities += ([p] * 10)}
      priorities.shuffle!

      jobs_dataset.import([:job_class, :priority, :job_schema_version], priorities.map{|p| ["Que::Job", p, Que.job_schema_version]})
    end

    def assert_poll(priorities:, locked:)
      ids = poll(priorities: priorities)

      assert_equal(
        locked,
        jobs_dataset.where(id: ids).group_by(:priority).select_hash(:priority, Sequel::Dataset::COUNT_OF_ALL_AS_COUNT),
      )
    end

    it "should retrieve jobs that match those priority requirements" do
      assert_poll(
        priorities: {5 => 5, 10 => 6, 25 => 7},
        locked: {10 => 10, 20 => 3},
      )
    end

    it "should behave properly if none of the jobs match the requirements" do
      assert_poll(
        priorities: {5 => 5},
        locked: {},
      )
    end
  end

  it "should only work a job whose scheduled time to run has passed" do
    future1 = Que::Job.enqueue(job_options: { run_at: Time.now + 30 }).que_attrs[:id]
    past    = Que::Job.enqueue(job_options: { run_at: Time.now - 30 }).que_attrs[:id]
    future2 = Que::Job.enqueue(job_options: { run_at: Time.now + 30 }).que_attrs[:id]

    assert_equal [past], poll
  end

  it "should prefer a job with lower priority" do
    # 1 is highest priority.
    [5, 4, 3, 2, 1, 2, 3, 4, 5].map { |p| Que::Job.enqueue priority: p }

    assert_equal(
      jobs_dataset.where{priority <= 3}.select_order_map(:id),
      poll(priorities: {10 => 5}).sort,
    )
  end

  it "should prefer a job that was scheduled to run longer ago" do
    id1 = Que::Job.enqueue(job_options: { run_at: Time.now - 30 }).que_attrs[:id]
    id2 = Que::Job.enqueue(job_options: { run_at: Time.now - 60 }).que_attrs[:id]
    id3 = Que::Job.enqueue(job_options: { run_at: Time.now - 30 }).que_attrs[:id]

    assert_equal [id2], poll(priorities: {200 => 1})
  end

  it "should prefer a job that was queued earlier" do
    run_at = Time.now - 30

    a, b, c = 3.times.map { Que::Job.enqueue(job_options: { run_at: run_at }).que_attrs[:id] }

    assert_equal [a, b], poll(priorities: {200 => 2})
  end

  it "should skip jobs that are advisory-locked" do
    a, b, c = 3.times.map { Que::Job.enqueue.que_attrs[:id] }

    begin
      DB.get{pg_advisory_lock(b)}

      assert_equal [a, c], poll
    ensure
      DB.get{pg_advisory_unlock(b)}
    end
  end

  it "should behave when being run concurrently by several connections" do
    q1, q2, q3, q4 = 4.times.map { Queue.new }

    # Poll 25 jobs each from four connections simultaneously.
    threads = 4.times.map do
      Thread.new do
        Que.checkout do |conn|
          q1.push nil
          q2.pop

          Thread.current[:jobs] = poll(priorities: {200 => 25}, override_connection: conn)

          q3.push nil
          q4.pop

          Que.execute "SELECT pg_advisory_unlock_all()"
        end
      end
    end

    # Hold until the four threads each have their own connection.
    4.times { q1.pop }

    Que.execute <<-SQL
      INSERT INTO que_jobs (job_class, priority, job_schema_version)
      SELECT 'Que::Job', 1, #{Que.job_schema_version}
      FROM generate_series(1, 100) AS i;
    SQL

    job_ids = jobs_dataset.select_order_map(:id)
    assert_equal 100, job_ids.count

    # Now that there are 100 jobs, let the four threads go.
    4.times { q2.push nil }
    4.times { q3.pop }

    assert_equal job_ids, threads.map{|t| t[:jobs]}.flatten.sort

    4.times { q4.push nil }
    threads.each(&:join)
  end

  describe "should_poll?" do
    let :poller do
      Que::Poller.new(
        connection: connection,
        queue: 'default',
        poll_interval: 5,
        poll_interval_variance: 0,
      )
    end

    before { Que::Poller.setup  (connection) }
    after  { Que::Poller.cleanup(connection) }

    it "should be true if the poller hasn't run before" do
      assert poller.should_poll?
    end

    it "should be true if the number of jobs returned from the last poll was greater than or equal to the lowest priority request" do
      job_ids_p10 = 5.times.map { Que::Job.enqueue(job_options: { priority: 10 }).que_attrs[:id] }
      job_ids_p20 = 2.times.map { Que::Job.enqueue(job_options: { priority: 20 }).que_attrs[:id] }

      result = poller.poll(priorities: { 10 => 6, 20 => 7 }, held_locks: Set.new)
      assert_equal (job_ids_p10 + job_ids_p20), result.map(&:id)

      assert_equal true, poller.should_poll?
    end

    it "should be false if the number of jobs returned from the last poll was less than the lowest priority request" do
      job_ids_p10 = 5.times.map { Que::Job.enqueue(job_options: { priority: 10 }).que_attrs[:id] }
      job_ids_p20 = 2.times.map { Que::Job.enqueue(job_options: { priority: 20 }).que_attrs[:id] }

      result = poller.poll(priorities: { 10 => 6, 20 => 8 }, held_locks: Set.new)
      assert_equal (job_ids_p10 + job_ids_p20), result.map(&:id)

      assert_equal false, poller.should_poll?
    end

    it "should be true if the number of jobs returned from the last poll was less than the lowest priority request, but the poll_interval has elapsed" do
      job_ids = 5.times.map { Que::Job.enqueue.que_attrs[:id] }

      result = poller.poll(priorities: { 500 => 7 }, held_locks: Set.new)
      assert_equal job_ids, result.map(&:id)

      poller.instance_variable_set(:@next_poll_at, Time.now)
      assert_equal true, poller.should_poll?
    end
  end
end
