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

  def get_message
    connection.wait_for_notify(1) do |channel, pid, payload|
      json = JSON.parse(payload, symbolize_names: true)
      assert_equal "job_change", json.delete(:message_type)
      return json
    end
    raise "No message!"
  end

  describe "when inserting a new job" do
    it "should issue a notification containing the job's class, queue, etc." do
      DB[:que_jobs].insert(job_class: "MyJobClass")

      assert_equal(
        {action: "insert", job_class: "MyJobClass", queue: "default"},
        get_message,
      )
    end

    describe "that is wrapped by ActiveJob" do
      it "should report the wrapped job class" do
        DB[:que_jobs].insert(
          job_class: "ActiveJob::QueueAdapters::QueAdapter::JobWrapper",
          data: JSON.dump(args: [{job_class: "WrappedJobClass"}]),
        )

        assert_equal(
          {action: "insert", job_class: "WrappedJobClass", queue: "default"},
          get_message,
        )
      end

      it "when the wrapped job class cannot be found should do the best it can" do
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
            data: JSON.dump(args: args),
          )

          assert_equal(
            {action: "insert", job_class: "ActiveJob::QueueAdapters::QueAdapter::JobWrapper", queue: "default"},
            get_message,
          )
        end
      end
    end
  end

  describe "when updating a job" do
    it "should issue a notification containing the job's class, error count, etc."
  end

  describe "when deleting a job" do
    it "should issue a notification containing the job's class, queue, etc."
  end
end
