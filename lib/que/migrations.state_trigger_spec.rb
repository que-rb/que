# frozen_string_literal: true

require 'spec_helper'

describe Que::Migrations, "que_state trigger" do
  attr_reader :connection

  around do |&block|
    super() do
      DEFAULT_QUE_POOL.checkout do |conn|
        begin
          @connection = conn
          conn.execute "LISTEN que_state"

          block.call
        ensure
          conn.execute "UNLISTEN que_state"
          conn.drain_notifications
        end
      end
    end
  end

  def get_message(timeout: 5, expect_nothing: false)
    connection.wait_for_notify(timeout) do |channel, pid, payload|
      json = JSON.parse(payload, symbolize_names: true)
      assert_equal "job_change", json.delete(:message_type)
      return json
    end
    raise "No message!" unless expect_nothing
  end

  def assert_notification(
    current_state:,
    previous_state:,
    queue: "default",
    job_class: "MyJobClass",
    tags: [],
    id: nil,
    run_at: nil
  )
    current_time = nil

    DB.transaction do
      result = yield
      current_time = DB.get{now.function}

      id     ||= result
      run_at ||= current_time
    end

    assert_equal(
      {
        queue: queue,
        job_class: job_class,
        tags: tags,
        previous_state: previous_state,
        current_state: current_state,
        id: id,
        run_at: run_at.utc.iso8601(6),
        time: current_time.utc.iso8601(6),
      },
      get_message,
    )
  end

  describe "the notification metadata" do
    it "should report the job's class and queue and tags" do
      assert_notification(
        job_class: "CustomJobClass",
        queue: "custom_queue",
        tags: ["tag_1", "tag_2"],
        previous_state: "nonexistent",
        current_state: "ready",
      ) do
        DB[:que_jobs].insert(
          job_class: "CustomJobClass",
          queue: "custom_queue",
          data: JSON.dump(tags: ["tag_1", "tag_2"]),
          job_schema_version: Que.job_schema_version,
        )
      end
    end

    describe "when the job is wrapped by ActiveJob" do
      it "should report the wrapped job class" do
        assert_notification(
          job_class: "WrappedJobClass",
          previous_state: "nonexistent",
          current_state: "ready",
        ) do
          DB[:que_jobs].insert(
            job_class: "ActiveJob::QueueAdapters::QueAdapter::JobWrapper",
            args: JSON.dump([{job_class: "WrappedJobClass"}]),
            job_schema_version: Que.job_schema_version,
          )
        end
      end

      it "and the wrapped job class cannot be found should report the wrapper" do
        [
          [4],
          [[]],
          [nil],
          [{}],
          [{other_key: 'value'}],
          ['string'],
        ].each do |args|
          assert_notification(
            job_class: "ActiveJob::QueueAdapters::QueAdapter::JobWrapper",
            previous_state: "nonexistent",
            current_state: "ready",
          ) do
            DB[:que_jobs].insert(
              job_class: "ActiveJob::QueueAdapters::QueAdapter::JobWrapper",
              args: JSON.dump(args),
              job_schema_version: Que.job_schema_version,
            )
          end
        end
      end
    end
  end

  # Spec the actual common state changes.

  describe "when inserting a new job" do
    it "that is ready should issue a notification containing the job's class, queue, etc." do
      assert_notification(
        previous_state: "nonexistent",
        current_state: "ready",
      ) do
        DB[:que_jobs].insert(job_class: "MyJobClass", job_schema_version: Que.job_schema_version)
      end
    end

    it "that is scheduled" do
      future = Time.now + 36000

      assert_notification(
        previous_state: "nonexistent",
        current_state: "scheduled",
        run_at: future,
      ) do
        DB[:que_jobs].insert(job_class: "MyJobClass", job_schema_version: Que.job_schema_version, run_at: future)
      end
    end
  end

  describe "when updating a job" do
    it "and marking it as finished should issue a notification containing the job's class, error count, etc." do
      record = DB[:que_jobs].returning(:id, :run_at).insert(job_class: "MyJobClass", job_schema_version: Que.job_schema_version).first
      assert get_message

      assert_notification(
        previous_state: "ready",
        current_state: "finished",
        id: record[:id],
        run_at: record[:run_at],
      ) do
        DB[:que_jobs].where(id: record[:id]).update(finished_at: Time.now)
      end
    end

    it "and marking it as errored" do
      record = DB[:que_jobs].returning(:id, :run_at).insert(job_class: "MyJobClass", job_schema_version: Que.job_schema_version).first
      assert get_message

      assert_notification(
        previous_state: "ready",
        current_state: "errored",
        id: record[:id],
        run_at: record[:run_at],
      ) do
        DB[:que_jobs].where(id: record[:id]).update(error_count: 1)
      end
    end

    it "and marking it as scheduled for the future" do
      record = DB[:que_jobs].returning(:id, :run_at).insert(job_class: "MyJobClass", job_schema_version: Que.job_schema_version).first
      assert get_message

      future = Time.now + 36000

      assert_notification(
        previous_state: "ready",
        current_state: "scheduled",
        id: record[:id],
        run_at: future,
      ) do
        DB[:que_jobs].where(id: record[:id]).update(run_at: future)
      end
    end

    it "and marking it as expired" do
      record = DB[:que_jobs].returning(:id, :run_at).insert(job_class: "MyJobClass", job_schema_version: Que.job_schema_version).first
      assert get_message

      assert_notification(
        previous_state: "ready",
        current_state: "expired",
        id: record[:id],
        run_at: record[:run_at],
      ) do
        DB[:que_jobs].where(id: record[:id]).update(expired_at: Time.now)
      end
    end

    it "and not changing the state should not emit a message" do
      id = DB[:que_jobs].insert(job_class: "MyJobClass", job_schema_version: Que.job_schema_version, run_at: Time.now + 36000)

      assert get_message

      assert_equal 1, DB[:que_jobs].where(id: id).update(run_at: Time.now + 72000)

      assert_nil get_message(timeout: 0.1, expect_nothing: true)
    end
  end

  describe "when deleting a job" do
    it "should issue a notification containing the job's class, queue, etc." do
      record = DB[:que_jobs].returning(:id, :run_at).insert(job_class: "MyJobClass", job_schema_version: Que.job_schema_version).first
      assert get_message

      assert_notification(
        previous_state: "ready",
        current_state: "nonexistent",
        id: record[:id],
        run_at: record[:run_at],
      ) do
        DB[:que_jobs].where(id: record[:id]).delete
      end
    end
  end
end
