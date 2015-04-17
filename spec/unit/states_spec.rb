require 'spec_helper'

describe Que, '.job_states' do
  it "should return a list of the jobs currently being run, and which Ruby processes are working them" do
    BlockJob.enqueue priority: 2

    # Ensure that the portion of the SQL query that accounts for bigint
    # job_ids functions correctly.
    DB[:que_jobs].update(job_id: 2**33)

    locker = Que::Locker.new
    $q1.pop

    states = Que.job_states
    states.length.should be 1

    $q2.push nil
    locker.stop

    state = states.first
    state.keys.should == %i(priority run_at job_id job_class args error_count last_error ruby_hostname ruby_pid)

    state[:priority].should == 2
    state[:run_at].should be_within(3).of Time.now
    state[:job_id].should == 2**33
    state[:job_class].should == 'BlockJob'
    state[:args].should == []
    state[:error_count].should == 0
    state[:last_error].should be nil

    state[:ruby_hostname].should == Socket.gethostname
    state[:ruby_pid].should == Process.pid
  end
end
