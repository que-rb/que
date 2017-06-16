# frozen_string_literal: true

require 'spec_helper'

describe Que::Listener do
  let :listener do
    Que::Listener.new(pool: QUE_POOL)
  end

  let :connection do
    @connection
  end

  let :pid do
    connection.backend_pid
  end

  around do |&block|
    QUE_POOL.checkout do |conn|
      begin
        listener.listen
        @connection = conn

        super(&block)
      ensure
        listener.unlisten
      end
    end
  end

  def notify(payload)
    payload = JSON.dump(payload) unless payload.is_a?(String)
    DB.notify("que_listener_#{pid}", payload: payload)
  end

  describe "wait_for_messages" do
    it "should return empty if there were no messages by the timeout" do
      assert_equal({}, listener.wait_for_messages(0.0001))
    end

    it "should return messages to the locker in bulk by type" do
      5.times do |i|
        notify(message_type: 'test_type_1', value: i)
        notify(message_type: 'test_type_2', value: i)
      end

      assert_equal(
        {
          test_type_1: 5.times.map{|i| {value: i}},
          test_type_2: 5.times.map{|i| {value: i}},
        },
        listener.wait_for_messages(0.0001),
      )
    end

    it "should be resilient to messages that aren't valid JSON" do
      notify 'blah'

      assert_equal({}, listener.wait_for_messages(0.0001))
    end
  end

  describe "unlisten" do
    it "should stop listening for new messages" do
      notify(message_type: 'blah')
      {} while connection.notifies

      listener.unlisten
      notify(message_type: 'blah')

      # Execute a new query to fetch any new notifications.
      connection.async_exec "SELECT 1"
      assert_nil connection.notifies
    end

    it "when unlistening should not leave any residual messages" do
      5.times { notify(message_type: 'blah') }

      listener.unlisten
      assert_nil connection.notifies

      # Execute a new query to fetch any remaining notifications.
      connection.async_exec "SELECT 1"
      assert_nil connection.notifies
    end
  end

  describe "message processing" do
    describe "for new_job messages" do
      it "should convert run_at values to Times"
    end
  end
end
