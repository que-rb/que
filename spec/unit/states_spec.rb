# frozen_string_literal: true

require 'spec_helper'

describe Que, '.job_states' do
  it "should return a list of the jobs currently being run" do
    BlockJob.enqueue priority: 2

    # Ensure that the portion of the SQL query that accounts for bigint
    # job_ids functions correctly.
    jobs.update(id: 2**33)

    locker = Que::Locker.new
    $q1.pop

    states = Que.job_states
    assert_equal 1, states.length

    $q2.push nil
    locker.stop!

    state = states.first
    assert_equal \
      %i(priority run_at id job_class error_count last_error_message queue
        last_error_backtrace is_processed data ruby_hostname ruby_pid),
      state.keys

    assert_equal 2, state[:priority]
    assert_in_delta state[:run_at], Time.now, 3
    assert_equal 2**33, state[:id]
    assert_equal 'BlockJob', state[:job_class]
    assert_equal({args: []}, state[:data])
    assert_equal 0, state[:error_count]
    assert_nil state.fetch(:last_error_message)
    assert_nil state.fetch(:last_error_backtrace)
    assert_equal false, state.fetch(:is_processed)

    assert_equal Socket.gethostname, state[:ruby_hostname]
    assert_equal Process.pid, state[:ruby_pid]
  end
end
