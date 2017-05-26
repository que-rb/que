# frozen_string_literal: true

require 'spec_helper'

describe Que do
  def assert_constraint_error(name, &block)
    e = assert_raises(Sequel::CheckConstraintViolation, &block)
    assert_includes e.message, "violates check constraint \"#{name}\""
  end

  describe "que_jobs table constraints" do
    it "should make sure that a job has valid arguments" do
      assert_constraint_error 'data_format' do
        DB[:que_jobs].
          insert(job_class: 'Que::Job', data: JSON.dump({}))
      end

      assert_constraint_error 'data_format' do
        DB[:que_jobs].
          insert(job_class: 'Que::Job', data: JSON.dump([]))
      end

      assert_constraint_error 'data_format' do
        DB[:que_jobs].
          insert(job_class: 'Que::Job', data: JSON.dump([{args: []}]))
      end

      assert_constraint_error 'data_format' do
        DB[:que_jobs].
          insert(job_class: 'Que::Job', data: '4')
      end

      assert_constraint_error 'data_format' do
        DB[:que_jobs].
          insert(job_class: 'Que::Job', data: JSON.dump({args: 4}))
      end
    end

    it "should make sure that a job queue name does not exceed 60 characters" do
      assert_constraint_error 'queue_length' do
        DB[:que_jobs].
          insert(job_class: 'Que::Job', queue: 'a' * 61)
      end
    end
  end

  describe "que_lockers table constraints" do
    it "should make sure that a locker has at least one queue name" do
      assert_constraint_error 'valid_queues' do
        DB[:que_lockers].
          insert(
            pid: 0,
            worker_count: 2,
            ruby_pid: 4,
            ruby_hostname: 'blah',
            listening: true,
            queues: Sequel.lit("'{}'::text[]"),
            worker_priorities: Sequel.pg_array([1, 2], :integer),
          )
      end
    end

    it "should make sure that a locker doesn't contain nested queue names" do
      assert_constraint_error 'valid_queues' do
        DB[:que_lockers].
          insert(
            pid: 0,
            worker_count: 2,
            ruby_pid: 4,
            ruby_hostname: 'blah',
            listening: true,
            queues: Sequel.pg_array([
              Sequel.pg_array(['a']),
              Sequel.pg_array(['b']),
            ]),
            worker_priorities: Sequel.pg_array([1, 2], :integer),
          )
      end
    end
  end
end
