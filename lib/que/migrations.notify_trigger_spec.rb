# frozen_string_literal: true

require 'spec_helper'

describe Que::Migrations, "notification trigger" do
  it "should notify a locker if one is listening" do
    DB.synchronize do |conn|
      begin
        DB[:que_lockers].insert(
          pid:           1,
          worker_count:  4,
          worker_priorities: Sequel.pg_array([1, 2, 3, 4], :integer),
          ruby_pid:      Process.pid,
          ruby_hostname: Socket.gethostname,
          queues:        Sequel.pg_array(['default']),
          listening:     true,
        )

        notify_pid =
          Que.execute("SELECT pg_backend_pid()").first[:pg_backend_pid].to_i

        conn.async_exec "LISTEN que_listener_1"

        Que::Job.enqueue
        job = jobs_dataset.first

        conn.wait_for_notify do |channel, pid, payload|
          assert_equal 'que_listener_1', channel
          assert_equal notify_pid, pid

          json = JSON.load(payload)
          assert_equal %w(id message_type priority run_at), json.keys.sort
          assert_equal 'new_job', json['message_type']
          assert_equal job[:id], json['id']
          assert_equal 100, json['priority']
          assert_in_delta Time.parse(json['run_at']), Time.now, 3
        end

        assert_nil conn.wait_for_notify(0.01)
      ensure
        conn.async_exec "UNLISTEN *"
      end
    end
  end

  it "should not notify a locker if run_at is in the future" do
    DB.synchronize do |conn|
      begin
        DB[:que_lockers].insert(
          pid:           1,
          worker_count:  4,
          worker_priorities: Sequel.pg_array([1, 2, 3, 4], :integer),
          ruby_pid:      Process.pid,
          ruby_hostname: Socket.gethostname,
          queues:        Sequel.pg_array(['default']),
          listening:     true,
        )

        conn.async_exec "LISTEN que_listener_1"

        Que::Job.enqueue run_at: Time.now + 60

        assert_nil conn.wait_for_notify(0.01)
      ensure
        conn.async_exec "UNLISTEN *"
      end
    end
  end

  it "should cycle between different lockers weighted by their worker_counts" do
    DB.synchronize do |conn|
      begin
        DB[:que_lockers].insert(
          pid:           1,
          worker_count:  1,
          worker_priorities: Sequel.pg_array([1], :integer),
          ruby_pid:      Process.pid,
          ruby_hostname: Socket.gethostname,
          queues:        Sequel.pg_array(['default']),
          listening:     true,
        )

        DB[:que_lockers].insert(
          pid:           2,
          worker_count:  2,
          worker_priorities: Sequel.pg_array([1, 2], :integer),
          ruby_pid:      Process.pid,
          ruby_hostname: Socket.gethostname,
          queues:        Sequel.pg_array(['default']),
          listening:     true,
        )

        notify_pid =
          Que.execute("SELECT pg_backend_pid()").first[:pg_backend_pid].to_i

        conn.async_exec "LISTEN que_listener_1; LISTEN que_listener_2"

        channels = 6.times.map { Que::Job.enqueue; conn.wait_for_notify }
        assert_equal \
          (['que_listener_1'] * 2 + ['que_listener_2'] * 4),
          channels.sort

        assert_nil conn.wait_for_notify(0.01)
      ensure
        conn.async_exec "UNLISTEN *"
      end
    end
  end

  it "should ignore lockers that are marked as not listening" do
    DB.synchronize do |conn|
      begin
        DB[:que_lockers].insert(
          pid:           1,
          worker_count:  4,
          worker_priorities: Sequel.pg_array([1, 2, 3, 4], :integer),
          ruby_pid:      Process.pid,
          ruby_hostname: Socket.gethostname,
          queues:        Sequel.pg_array(['default']),
          listening:     false,
        )

        notify_pid =
          Que.execute("SELECT pg_backend_pid()").first[:pg_backend_pid].to_i

        conn.async_exec "LISTEN que_listener_1"

        Que::Job.enqueue
        job = jobs_dataset.first
        assert_nil conn.wait_for_notify(0.01)
      ensure
        conn.async_exec "UNLISTEN *"
      end
    end
  end

  it "should ignore lockers that aren't listening to that queue" do
    DB.synchronize do |conn|
      begin
        DB[:que_lockers].insert(
          pid:           1,
          worker_count:  1,
          worker_priorities: Sequel.pg_array([1], :integer),
          ruby_pid:      Process.pid,
          ruby_hostname: Socket.gethostname,
          queues:        Sequel.pg_array(['default']),
          listening:     true,
        )

        DB[:que_lockers].insert(
          pid:           2,
          worker_count:  2,
          worker_priorities: Sequel.pg_array([1, 2], :integer),
          ruby_pid:      Process.pid,
          ruby_hostname: Socket.gethostname,
          queues:        Sequel.pg_array(['other_queue']),
          listening:     true,
        )

        notify_pid =
          Que.execute("SELECT pg_backend_pid()").first[:pg_backend_pid].to_i

        conn.async_exec "LISTEN que_listener_1; LISTEN que_listener_2"

        channels = 6.times.map { Que::Job.enqueue; conn.wait_for_notify }
        assert_equal \
          (['que_listener_1'] * 6),
          channels

        assert_nil conn.wait_for_notify(0.01)
      ensure
        conn.async_exec "UNLISTEN *"
      end
    end
  end
end
