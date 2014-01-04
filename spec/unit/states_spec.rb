require 'spec_helper'

describe Que, '.worker_states' do
  it "should return a list of the job types in the queue, their counts and the number of each currently running" do
    Que.adapter = QUE_ADAPTERS[:connection_pool]

    class WorkerStateJob < BlockJob
      def run
        $pid = Que.execute("select pg_backend_pid()").first['pg_backend_pid']
        super
      end
    end

    WorkerStateJob.queue :priority => 2

    # Ensure that the portion of the SQL query that accounts for bigint
    # job_ids functions correctly.
    DB[:que_jobs].update(:job_id => 2**33)

    begin
      t = Thread.new do
        Que::Job.work
      end

      $q1.pop

      states = Que.worker_states
      states.length.should be 1

      state = states.first
      state.keys.should == %w(priority run_at job_id job_class args error_count last_error pg_backend_pid pg_state pg_state_changed_at pg_last_query pg_last_query_started_at pg_transaction_started_at pg_waiting_on_lock)

      state[:priority].should == '2'
      Time.parse(state[:run_at]).should be_within(3).of Time.now
      state[:job_id].should == (2**33).to_s
      state[:job_class].should == 'WorkerStateJob'
      state[:args].should == '[]'
      state[:error_count].should == '0'
      state[:last_error].should be nil

      state[:pg_backend_pid].should == $pid.to_s
      state[:pg_state].should == 'idle'
      Time.parse(state[:pg_state_changed_at]).should be_within(3).of Time.now
      state[:pg_last_query].should == 'select pg_backend_pid()'
      Time.parse(state[:pg_last_query_started_at]).should be_within(3).of Time.now
      state[:pg_transaction_started_at].should == nil
      state[:pg_waiting_on_lock].should == 'f'
    ensure
      if t
        t.kill
        t.join
      end
    end
  end if QUE_ADAPTERS[:connection_pool]
end
