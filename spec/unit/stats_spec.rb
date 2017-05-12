# frozen_string_literal: true

require 'spec_helper'

describe Que, '.job_stats' do
  it "should return a list of the job types in the queue" do
    BlockJob.enqueue
    Que::Job.enqueue

    # Have to tweak the id to ensure that the portion of the SQL query
    # that accounts for bigint ids functions correctly.
    old = Time.now - 3600
    jobs.where(job_class: "Que::Job").
      update(id: 2**33, error_count: 5, run_at: old)

    Que::Job.enqueue

    begin
      DB.get{pg_advisory_lock(2**33)}

      stats = Que.job_stats
      assert_equal 2, stats.length

      qj, bj = stats

      assert_equal \
        %i(job_class count count_working count_errored
          highest_error_count oldest_run_at),
        qj.keys

      assert_equal 'Que::Job', qj[:job_class]
      assert_equal 2, qj[:count]
      assert_equal 1, qj[:count_working]
      assert_equal 1, qj[:count_errored]
      assert_equal 5, qj[:highest_error_count]
      assert_in_delta qj[:oldest_run_at], old, 3

      assert_equal 'BlockJob', bj[:job_class]
      assert_equal 1, bj[:count]
      assert_equal 0, bj[:count_working]
      assert_equal 0, bj[:count_errored]
      assert_equal 0, bj[:highest_error_count]
      assert_in_delta bj[:oldest_run_at], Time.now, 3
    ensure
      DB.get{pg_advisory_unlock_all.function}
    end
  end
end
