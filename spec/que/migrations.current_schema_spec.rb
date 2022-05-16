# frozen_string_literal: true

require 'spec_helper'

describe Que::Migrations, "current schema" do
  def assert_constraint_error(name, &block)
    e = assert_raises(Sequel::CheckConstraintViolation, &block)
    assert_includes e.message, "violates check constraint \"#{name}\""
  end

  describe "que_jobs table constraints" do
    it "should make sure that a job has valid arguments" do
      [
        {},
        4,
        "string",
        nil,
        true
      ].each do |args|
        assert_constraint_error 'valid_args' do
          DB[:que_jobs].
            insert(job_class: 'Que::Job', job_schema_version: Que.job_schema_version, args: JSON.generate(args, quirks_mode: true))
        end
      end
    end

    it "should make sure that a job has valid tags" do
      assert_constraint_error 'valid_data' do
        DB[:que_jobs].
          insert(job_class: 'Que::Job', job_schema_version: Que.job_schema_version, data: JSON.dump(tags: {}))
      end

      [
        {},
        4,
        "string",
        nil,
        true,
        %w[a b c d e f], # More than 5 elements.
      ].each do |tags|
        assert_constraint_error 'valid_data' do
          DB[:que_jobs].
            insert(job_class: 'Que::Job', job_schema_version: Que.job_schema_version, data: JSON.dump(tags: tags))
        end
      end

      [
        [1],
        [true],
        [nil],
        [[]],
        [{}],
        ["a" * 101],
      ].each do |tags|
        assert_constraint_error 'valid_data' do
          DB[:que_jobs].
            insert(job_class: 'Que::Job', job_schema_version: Que.job_schema_version, data: JSON.dump(tags: tags))
        end

        assert_constraint_error 'valid_data' do
          DB[:que_jobs].
            insert(job_class: 'Que::Job', job_schema_version: Que.job_schema_version, data: JSON.dump(tags: (tags << "valid_tag").shuffle))
        end
      end
    end

    it "should make sure that a job_class does not exceed 200 characters" do
      assert_constraint_error 'job_class_length' do
        DB[:que_jobs].
          insert(job_class: 'a' * 201, job_schema_version: Que.job_schema_version)
      end

      # Make sure the check constraint also handles wrapped ActiveJob jobs.
      assert_constraint_error 'job_class_length' do
        DB[:que_jobs].
          insert(
            job_class: 'ActiveJob::QueueAdapters::QueAdapter::JobWrapper',
            args: JSON.dump([{job_class: '2' * 501}]),
            job_schema_version: Que.job_schema_version,
          )
      end

      # If the job_class is the ActiveJob wrapper but the args don't look like
      # we expect, just ignore it.
      DB[:que_jobs].
        insert(
          job_class: 'ActiveJob::QueueAdapters::QueAdapter::JobWrapper',
          data: JSON.dump(
            args: [],
            tags: [],
          ),
          job_schema_version: Que.job_schema_version,
        )
    end

    it "should make sure that a queue does not exceed 100 characters" do
      assert_constraint_error 'queue_length' do
        DB[:que_jobs].
          insert(job_class: 'Que::Job', job_schema_version: Que.job_schema_version, queue: 'a' * 101)
      end
    end

    it "should make sure that a job error message does not exceed 500 characters" do
      assert_constraint_error 'error_length' do
        DB[:que_jobs].
          insert(job_class: 'Que::Job', job_schema_version: Que.job_schema_version, last_error_message: 'a' * 501)
      end
    end

    it "should make sure that a job error backtrace does not exceed 10000 characters" do
      assert_constraint_error 'error_length' do
        DB[:que_jobs].
          insert(job_class: 'Que::Job', job_schema_version: Que.job_schema_version, last_error_backtrace: 'a' * 10001)
      end
    end
  end

  describe "que_lockers table constraints" do
    let :locker_attrs do
      {
        pid: 0,
        worker_count: 2,
        ruby_pid: 4,
        ruby_hostname: 'blah',
        listening: true,
        queues: Sequel.lit("'{queue_name}'::text[]"),
        worker_priorities: Sequel.pg_array([1, 2], :integer),
      }
    end

    it "should allow a valid record" do
      DB[:que_lockers].insert(locker_attrs)
    end

    it "should make sure that a locker has at least one worker priority" do
      assert_constraint_error 'valid_worker_priorities' do
        locker_attrs[:worker_priorities] = Sequel.lit("'{}'::integer[]")
        DB[:que_lockers].insert(locker_attrs)
      end
    end

    it "should make sure that a locker doesn't nest worker priorities" do
      assert_constraint_error 'valid_worker_priorities' do
        locker_attrs[:worker_priorities] = Sequel.pg_array([
          Sequel.pg_array([1, 2]),
          Sequel.pg_array([1, 2]),
        ])
        DB[:que_lockers].insert(locker_attrs)
      end
    end

    it "should make sure that a locker has at least one queue name" do
      assert_constraint_error 'valid_queues' do
        locker_attrs[:queues] = Sequel.lit("'{}'::text[]")
        DB[:que_lockers].insert(locker_attrs)
      end
    end

    it "should make sure that a locker doesn't contain nested queue names" do
      assert_constraint_error 'valid_queues' do
        locker_attrs[:queues] = Sequel.pg_array([
          Sequel.pg_array(['a']),
          Sequel.pg_array(['b']),
        ])
        DB[:que_lockers].insert(locker_attrs)
      end
    end
  end

  describe "que_values table constraints" do
    let :value_attrs do
      {
        key: "string",
        value: JSON.dump(jsonb_key: "jsonb_value"),
      }
    end

    it "should allow a valid record" do
      DB[:que_values].insert(value_attrs)
    end

    it "should make sure that value is an object" do
      assert_constraint_error 'valid_value' do
        value_attrs[:value] = JSON.dump([])
        DB[:que_values].insert(value_attrs)
      end

      assert_constraint_error 'valid_value' do
        value_attrs[:value] = JSON.generate(5, quirks_mode: true)
        DB[:que_values].insert(value_attrs)
      end

      assert_constraint_error 'valid_value' do
        value_attrs[:value] = JSON.generate("string", quirks_mode: true)
        DB[:que_values].insert(value_attrs)
      end
    end
  end
end
