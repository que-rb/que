# frozen_string_literal: true

require 'spec_helper'

describe Que::Migrations, "job_available trigger" do
  let :locker_attrs do
    {
      pid:                1,
      worker_count:       4,
      worker_priorities:  Sequel.pg_array([1, 2, 3, 4], :integer),
      ruby_pid:           Process.pid,
      ruby_hostname:      Socket.gethostname,
      queues:             Sequel.pg_array(['default']),
      listening:          true,
      job_schema_version: Que.job_schema_version,
    }
  end

  def listen_connection
    DB.synchronize do |conn|
      begin
        yield conn
      ensure
        conn.async_exec "UNLISTEN *"
        {} while conn.notifies
      end
    end
  end

  it "should notify a locker if one is listening" do
    listen_connection do |conn|
      DB[:que_lockers].insert(locker_attrs)

      notify_pid = nil

      Que.checkout do
        notify_pid =
          Que.execute("SELECT pg_backend_pid()").first[:pg_backend_pid].to_i

        conn.async_exec "LISTEN que_listener_1"

        Que::Job.enqueue
      end

      job = jobs_dataset.first

      conn.wait_for_notify do |channel, pid, payload|
        assert_equal 'que_listener_1', channel
        assert_equal notify_pid, pid

        json = JSON.load(payload)
        assert_equal %w(id message_type priority queue run_at), json.keys.sort
        assert_equal 'default', json['queue']
        assert_equal 'job_available', json['message_type']
        assert_equal job[:id], json['id']
        assert_equal 100, json['priority']
        assert_in_delta Time.iso8601(json['run_at']), Time.now.utc, QueSpec::TIME_SKEW
      end

      assert_nil conn.wait_for_notify(0.01)
    end
  end

  it "should not notify a locker if run_at is in the future" do
    listen_connection do |conn|
      DB[:que_lockers].insert(locker_attrs)

      conn.async_exec "LISTEN que_listener_1"

      Que::Job.enqueue(job_options: { run_at: Time.now + 60 })

      assert_nil conn.wait_for_notify(0.01)
    end
  end

  it "should cycle between different lockers weighted by their worker_counts" do
    listen_connection do |conn|
      DB[:que_lockers].insert(locker_attrs)

      DB[:que_lockers].insert(
        locker_attrs.merge(
          pid:           2,
          worker_count:  2,
          worker_priorities: Sequel.pg_array([1, 2], :integer),
        )
      )

      conn.async_exec "LISTEN que_listener_1; LISTEN que_listener_2"

      channels = 12.times.map { Que::Job.enqueue; conn.wait_for_notify }
      assert_equal \
        (['que_listener_1'] * 8 + ['que_listener_2'] * 4),
        channels.sort

      assert_nil conn.wait_for_notify(0.01)
    end
  end

  it "should ignore lockers that are marked as not listening" do
    listen_connection do |conn|
      DB[:que_lockers].insert(locker_attrs.merge(listening: false))
      conn.async_exec "LISTEN que_listener_1"

      Que::Job.enqueue
      job = jobs_dataset.first
      assert_nil conn.wait_for_notify(0.01)
    end
  end

  it "should ignore lockers that aren't listening to that queue" do
    listen_connection do |conn|
      DB[:que_lockers].insert(locker_attrs)

      DB[:que_lockers].insert(
        locker_attrs.merge(
          pid:               2,
          worker_count:      2,
          worker_priorities: Sequel.pg_array([1, 2], :integer),
          queues:            Sequel.pg_array(['other_queue']),
        )
      )

      conn.async_exec "LISTEN que_listener_1; LISTEN que_listener_2"

      channels = 6.times.map { Que::Job.enqueue; conn.wait_for_notify }
      assert_equal \
        (['que_listener_1'] * 6),
        channels

      assert_nil conn.wait_for_notify(0.01)
    end
  end
end
