# frozen_string_literal: true

require 'spec_helper'

describe Que::Utils::Introspection do
  describe 'job_stats' do
    it "should return a list of the unfinished job types in the queue" do
      BlockJob.enqueue
      3.times { Que::Job.enqueue }

      # Mark one job as finished, it shouldn't show up in the aggregates.
      ids = DB[:que_jobs].where(job_class: "Que::Job").select_map(:id)
      DB[:que_jobs].where(id: ids[0]).update(finished_at: Time.now)

      old = Time.now - 3600
      DB[:que_jobs].where(id: ids[1]).update(error_count: 5, run_at: old)

      begin
        DB.get{pg_advisory_lock(ids[2])}

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
        assert_in_delta qj[:oldest_run_at], old, QueSpec::TIME_SKEW

        assert_equal 'BlockJob', bj[:job_class]
        assert_equal 1, bj[:count]
        assert_equal 0, bj[:count_working]
        assert_equal 0, bj[:count_errored]
        assert_equal 0, bj[:highest_error_count]
        assert_in_delta bj[:oldest_run_at], Time.now, QueSpec::TIME_SKEW
      ensure
        DB.get(Sequel.function(:pg_advisory_unlock_all))
      end
    end
  end

  describe 'job_states' do
    it "should return a list of the jobs currently being run" do
      BlockJob.enqueue(job_options: { priority: 2 })

      # Ensure that the portion of the SQL query that accounts for bigint
      # job_ids functions correctly.
      jobs_dataset.update(id: 2**33)

      locker = Que::Locker.new
      $q1.pop

      states = Que.job_states
      assert_equal 1, states.length

      $q2.push nil
      locker.stop!

      state = states.first
      expected_keys = %i(priority run_at id job_class error_count last_error_message queue
      last_error_backtrace finished_at expired_at args data job_schema_version kwargs ruby_hostname ruby_pid first_run_at)

      assert_equal expected_keys.sort, state.keys.sort

      assert_equal 2, state[:priority]
      assert_in_delta state[:run_at], Time.now, QueSpec::TIME_SKEW
      assert_equal 2**33, state[:id]
      assert_equal 'BlockJob', state[:job_class]
      assert_equal [], state[:args]
      assert_equal({}, state[:data])
      assert_equal 0, state[:error_count]
      assert_nil state.fetch(:last_error_message)
      assert_nil state.fetch(:last_error_backtrace)

      assert_equal Socket.gethostname, state[:ruby_hostname]
      assert_equal Process.pid, state[:ruby_pid]
    end
  end
end
