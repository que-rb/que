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

  it "should return messages to the locker in bulk by type"

  it "should pre-process new_job messages"

  it "should be resilient to messages that aren't valid JSON" do
    notify 'blah'

    assert_nil listener.wait_for_messages(0.0001)
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
end
