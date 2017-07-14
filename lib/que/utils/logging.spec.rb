# frozen_string_literal: true

require 'spec_helper'

describe Que::Utils::Logging do
  describe "log" do
    it "should record the library and hostname and thread id in JSON" do
      Que.log event: "blah", source: 4
      assert_equal 1, QUE_LOGGER.messages.count

      message = JSON.load(QUE_LOGGER.messages.first)
      assert_equal 'que', message['lib']
      assert_equal Socket.gethostname, message['hostname']
      assert_equal Process.pid, message['pid']
      assert_equal 'blah', message['event']
      assert_equal 4, message['source']
      assert_equal Thread.current.object_id, message['thread']
    end

    it "should respect a callable set as the logger" do
      QUE_LOGGER.messages.clear
      called = false
      Que.logger = proc { called = true; QUE_LOGGER }
      Que.log(event: "blah")
      assert called
      refute_empty QUE_LOGGER.messages
    end

    it "should not raise an error when no logger is present" do
      Que.logger = nil
      assert_nil Que.log(event: "blah")
      assert_empty QUE_LOGGER.messages
    end

    it "should allow the use of a custom log formatter" do
      Que.log_formatter = proc { |data| "Logged event is #{data[:event]}" }
      Que.log event: 'my_event'
      assert_equal 1, QUE_LOGGER.messages.count
      assert_equal "Logged event is my_event", QUE_LOGGER.messages.first
    end

    it "should not log anything if the logging formatter returns falsey" do
      Que.log_formatter = proc { |data| false }
      Que.log event: "blah"
      assert_empty QUE_LOGGER.messages
    end

    it "should use a :level option to set the log level if one exists" do
      begin
        Que.logger = o = Object.new

        def o.method_missing(level, message)
          $level = level
          $message = message
        end

        Que.log message: 'one'
        assert_equal :info, $level
        assert_equal 'one', JSON.load($message)['message']

        Que.log message: 'two', level: 'debug'
        assert_equal :debug, $level
        assert_equal 'two', JSON.load($message)['message']
      ensure
        $level = $message = nil
      end
    end

    it "should just log a generic message if the log formatter raises an error" do
      Que.log_formatter = proc { |m| raise "Blah!" }

      Que.log event: "blah", source: 4
      assert_equal 1, QUE_LOGGER.messages.count

      message = QUE_LOGGER.messages.first
      assert message.start_with?(
        "Error raised from Que.log_formatter proc: RuntimeError: Blah!"
      )
    end
  end

  describe "get_logger" do
    it "should return nil if the logger is nil" do
      Que.logger = nil
      assert_nil Que.get_logger
    end

    it "should return the logger if it's a non-callable" do
      Que.logger = 5
      assert_equal 5, Que.get_logger
    end

    it "should return the results of a callable" do
      Que.logger = proc { 'blah' }
      assert_equal 'blah', Que.get_logger
    end
  end

  describe "internal_log" do
    it "should be a no-op if there's no internal_logger set" do
      Que.internal_logger = nil
      assert_nil Que.internal_log(:thing_happened) { raise "Blah!" }
    end

    it "should output whatever's in the block to the internal_logger" do
      Que.internal_log(:thing_happened) { {key: "Blah!"} }
      Que.internal_log(:thing_happened) { {key: "Blah again!"} }

      assert_equal(
        [
          "{\"key\":\"Blah!\",\"internal_event\":\"thing_happened\"}",
          "{\"key\":\"Blah again!\",\"internal_event\":\"thing_happened\"}",
        ],
        QUE_INTERNAL_LOGGER.messages,
      )
    end
  end
end
