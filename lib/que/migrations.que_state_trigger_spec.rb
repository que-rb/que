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

  describe "the notification metadata" do
    it "should report the job's class and queue and tags" do
      DB[:que_jobs].insert(
        job_class: "CustomJobClass",
        queue: "custom_queue",
        data: JSON.dump(args: [], tags: ["tag_1", "tag_2"]),
      )

      assert_equal(
        {
          queue: "custom_queue",
          job_class: "CustomJobClass",
          tags: ["tag_1", "tag_2"],
          previous_state: "nonexistent",
          current_state: "ready",
        },
        get_message,
      )
    end

    describe "when the job is wrapped by ActiveJob" do
      it "should report the wrapped job class" do
        DB[:que_jobs].insert(
          job_class: "ActiveJob::QueueAdapters::QueAdapter::JobWrapper",
          data: JSON.dump(args: [{job_class: "WrappedJobClass"}], tags: []),
        )

        assert_equal(
          {
            queue: "default",
            job_class: "WrappedJobClass",
            tags: [],
            previous_state: "nonexistent",
            current_state: "ready",
          },
          get_message,
        )
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
          DB[:que_jobs].insert(
            job_class: "ActiveJob::QueueAdapters::QueAdapter::JobWrapper",
            data: JSON.dump(args: args, tags: []),
          )

          assert_equal(
            {
              queue: "default",
              job_class: "ActiveJob::QueueAdapters::QueAdapter::JobWrapper",
              tags: [],
              previous_state: "nonexistent",
              current_state: "ready",
            },
            get_message,
          )
        end
      end
    end
  end

  # Spec the actual common state changes.

  describe "when inserting a new job" do
    it "that is ready should issue a notification containing the job's class, queue, etc." do
      DB[:que_jobs].insert(job_class: "MyJobClass")

      assert_equal(
        {
          queue: "default",
          job_class: "MyJobClass",
          tags: [],
          previous_state: "nonexistent",
          current_state: "ready",
        },
        get_message,
      )
    end

    it "that is scheduled" do
      DB[:que_jobs].insert(job_class: "MyJobClass", run_at: Time.now + 36000)

      assert_equal(
        {
          queue: "default",
          job_class: "MyJobClass",
          tags: [],
          previous_state: "nonexistent",
          current_state: "scheduled",
        },
        get_message,
      )
    end
  end

  describe "when updating a job" do
    it "and marking it as finished should issue a notification containing the job's class, error count, etc." do
      id = DB[:que_jobs].insert(job_class: "MyJobClass")

      assert get_message

      assert_equal 1, DB[:que_jobs].where(id: id).update(finished_at: Time.now)

      assert_equal(
        {
          queue: "default",
          job_class: "MyJobClass",
          tags: [],
          previous_state: "ready",
          current_state: "finished",
        },
        get_message,
      )
    end

    it "and marking it as errored" do
      id = DB[:que_jobs].insert(job_class: "MyJobClass")

      assert get_message

      assert_equal 1, DB[:que_jobs].where(id: id).update(error_count: 1)

      assert_equal(
        {
          queue: "default",
          job_class: "MyJobClass",
          tags: [],
          previous_state: "ready",
          current_state: "errored",
        },
        get_message,
      )
    end

    it "and marking it as scheduled for the future" do
      id = DB[:que_jobs].insert(job_class: "MyJobClass")

      assert get_message

      assert_equal 1, DB[:que_jobs].where(id: id).update(run_at: Time.now + 36000)

      assert_equal(
        {
          queue: "default",
          job_class: "MyJobClass",
          tags: [],
          previous_state: "ready",
          current_state: "scheduled",
        },
        get_message,
      )
    end

    it "and not changing the state should not emit a message" do
      id = DB[:que_jobs].insert(job_class: "MyJobClass", run_at: Time.now + 36000)

      assert get_message

      assert_equal 1, DB[:que_jobs].where(id: id).update(run_at: Time.now + 72000)

      assert_nil get_message(timeout: 0.1, expect_nothing: true)
    end
  end

  describe "when deleting a job" do
    it "should issue a notification containing the job's class, queue, etc." do
      id = DB[:que_jobs].insert(job_class: "MyJobClass")

      assert get_message

      assert_equal 1, DB[:que_jobs].where(id: id).delete

      assert_equal(
        {
          queue: "default",
          job_class: "MyJobClass",
          tags: [],
          previous_state: "ready",
          current_state: "nonexistent",
        },
        get_message,
      )
    end
  end
end
