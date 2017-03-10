# frozen_string_literal: true

require 'spec_helper'

describe "An insertion into que_jobs" do
  it "should not fail if there are no lockers registered" do
    Que::Job.enqueue
    assert_equal ['Que::Job'], DB[:que_jobs].select_map(:job_class)
  end

  it "should notify a locker if one is listening" do
    DB.synchronize do |conn|
      begin
        DB[:que_lockers].insert pid:           1,
                                worker_count:  4,
                                ruby_pid:      Process.pid,
                                ruby_hostname: Socket.gethostname,
                                listening:     true

        notify_pid = Que.execute("SELECT pg_backend_pid()").first[:pg_backend_pid].to_i
        conn.async_exec "LISTEN que_locker_1"

        Que::Job.enqueue
        job = DB[:que_jobs].first

        conn.wait_for_notify do |channel, pid, payload|
          assert_equal 'que_locker_1', channel
          assert_equal notify_pid, pid

          json = JSON.load(payload)
          assert_equal %w(job_id priority run_at), json.keys.sort
          assert_equal job[:job_id], json['job_id']
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
        DB[:que_lockers].insert pid:           1,
                                worker_count:  4,
                                ruby_pid:      Process.pid,
                                ruby_hostname: Socket.gethostname,
                                listening:     true

        conn.async_exec "LISTEN que_locker_1"

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
        DB[:que_lockers].insert pid:           1,
                                worker_count:  1,
                                ruby_pid:      Process.pid,
                                ruby_hostname: Socket.gethostname,
                                listening:     true

        DB[:que_lockers].insert pid:           2,
                                worker_count:  2,
                                ruby_pid:      Process.pid,
                                ruby_hostname: Socket.gethostname,
                                listening:     true

        notify_pid = Que.execute("SELECT pg_backend_pid()").first[:pg_backend_pid].to_i
        conn.async_exec "LISTEN que_locker_1; LISTEN que_locker_2"

        channels = 6.times.map { Que::Job.enqueue; conn.wait_for_notify }
        assert_equal (['que_locker_1'] * 2 + ['que_locker_2'] * 4), channels.sort

        assert_nil conn.wait_for_notify(0.01)
      ensure
        conn.async_exec "UNLISTEN *"
      end
    end
  end

  it "should ignore lockers that are marked as not listening" do
    DB.synchronize do |conn|
      begin
        DB[:que_lockers].insert pid:           1,
                                worker_count:  4,
                                ruby_pid:      Process.pid,
                                ruby_hostname: Socket.gethostname,
                                listening:     false

        notify_pid = Que.execute("SELECT pg_backend_pid()").first[:pg_backend_pid].to_i
        conn.async_exec "LISTEN que_locker_1"

        Que::Job.enqueue
        job = DB[:que_jobs].first
        assert_nil conn.wait_for_notify(0.01)
      ensure
        conn.async_exec "UNLISTEN *"
      end
    end
  end
end
