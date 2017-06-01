# frozen_string_literal: true

require 'spec_helper'

describe Que, '.job_stats' do
  it "should return a list of the job types in the queue, their counts and the number of each currently running" do
    BlockJob.enqueue
    Que::Job.enqueue

    # Have to tweak the job_id to ensure that the portion of the SQL query
    # that accounts for bigint job_ids functions correctly.
    old = Time.now - 3600
    DB[:que_jobs].where(:job_class => "Que::Job").update(:job_id => 2**33, :error_count => 5, :run_at => old)

    Que::Job.enqueue

    begin
      DB.get{pg_advisory_lock(2**33)}

      stats = Que.job_stats
      stats.length.should == 2

      qj, bj = stats

      qj.keys.should == %w(queue job_class count count_working count_errored highest_error_count oldest_run_at)

      qj[:queue].should == ''
      qj[:job_class].should == 'Que::Job'
      qj[:count].should == 2
      qj[:count_working].should == 1
      qj[:count_errored].should == 1
      qj[:highest_error_count].should == 5
      qj[:oldest_run_at].should be_within(3).of old

      bj[:queue].should == ''
      bj[:job_class].should == 'BlockJob'
      bj[:count].should == 1
      bj[:count_working].should == 0
      bj[:count_errored].should == 0
      bj[:highest_error_count].should == 0
      bj[:oldest_run_at].should be_within(3).of Time.now
    ensure
      DB.get{pg_advisory_unlock_all.function}
    end
  end
end
