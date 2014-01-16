require 'spec_helper'

describe "An insertion into que_jobs" do
  it "should not fail if there are no listeners registered" do
    Que::Job.queue
    DB[:que_jobs].select_map(:job_class).should == ['Que::Job']
  end

  it "should notify a listener if one is available" do
    DB.synchronize do |conn|
      begin
        DB[:que_listeners].insert :pid           => 1,
                                  :worker_count  => 4,
                                  :ruby_pid      => Process.pid,
                                  :ruby_hostname => Socket.gethostname,
                                  :queue         => ''

        notify_pid = Que.execute("SELECT pg_backend_pid()").first[:pg_backend_pid].to_i
        conn.async_exec "LISTEN que_listener_1"

        Que::Job.queue
        job = DB[:que_jobs].first

        conn.wait_for_notify do |channel, pid, payload|
          channel.should == "que_listener_1"
          pid.should == notify_pid

          json = JSON.load(payload)
          json['job_id'].should == job[:job_id]
          json['queue'].should == job[:queue]
          json['job_class'].should == 'Que::Job'
          json['priority'].should == 100
          json['args'].should == []
        end

        conn.wait_for_notify(0.01).should be nil
      ensure
        conn.async_exec "UNLISTEN *"
      end
    end
  end

  it "should not notify listeners of different queues" do
    DB.synchronize do |conn|
      begin
        DB[:que_listeners].insert :pid           => 1,
                                  :worker_count  => 4,
                                  :ruby_pid      => Process.pid,
                                  :ruby_hostname => Socket.gethostname,
                                  :queue         => 'other_queue'

        notify_pid = Que.execute("SELECT pg_backend_pid()").first[:pg_backend_pid].to_i
        conn.async_exec "LISTEN que_listener_1"

        Que::Job.queue
        conn.wait_for_notify(0.01).should be nil
        DB[:que_jobs].delete

        Que::Job.queue :queue => 'other_queue'
        job = DB[:que_jobs].first

        conn.wait_for_notify do |channel, pid, payload|
          channel.should == "que_listener_1"
          pid.should == notify_pid

          json = JSON.load(payload)
          json['job_id'].should == job[:job_id]
          json['queue'].should == job[:queue]
          json['job_class'].should == 'Que::Job'
          json['priority'].should == 100
          json['args'].should == []
        end

        conn.wait_for_notify(0.01).should be nil
      ensure
        conn.async_exec "UNLISTEN *"
      end
    end
  end

  it "should cycle between different listeners weighted by their worker_counts" do
    DB.synchronize do |conn|
      begin
        DB[:que_listeners].insert :pid           => 1,
                                  :worker_count  => 1,
                                  :ruby_pid      => Process.pid,
                                  :ruby_hostname => Socket.gethostname,
                                  :queue         => ''

        DB[:que_listeners].insert :pid           => 2,
                                  :worker_count  => 2,
                                  :ruby_pid      => Process.pid,
                                  :ruby_hostname => Socket.gethostname,
                                  :queue         => ''

        notify_pid = Que.execute("SELECT pg_backend_pid()").first[:pg_backend_pid].to_i
        conn.async_exec "LISTEN que_listener_1; LISTEN que_listener_2"

        channels = 6.times.map { Que::Job.queue; conn.wait_for_notify }
        channels.sort.should == ['que_listener_1'] * 2 + ['que_listener_2'] * 4

        conn.wait_for_notify(0.01).should be nil
      ensure
        conn.async_exec "UNLISTEN *"
      end
    end
  end
end
