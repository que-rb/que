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
      begin
        QUE_LOGGER.messages.clear
        called = false
        Que.logger = proc { called = true; QUE_LOGGER }
        Que.log(event: "blah")
        assert called
        skip "Use a stub?"
      ensure
        Que.logger = QUE_LOGGER
      end
    end

    it "should not raise an error when no logger is present" do
      begin
        Que.logger = nil
        assert_nil Que.log(event: "blah")
      ensure
        Que.logger = QUE_LOGGER
      end
    end

    it "should allow the use of a custom log formatter" do
      begin
        Que.log_formatter = proc { |data| "Logged event is #{data[:event]}" }
        Que.log event: 'my_event'
        assert_equal 1, QUE_LOGGER.messages.count
        assert_equal "Logged event is my_event", QUE_LOGGER.messages.first
      ensure
        Que.log_formatter = nil
      end
    end

    it "should not log anything if the logging formatter returns falsey" do
      begin
        Que.log_formatter = proc { |data| false }
        Que.log event: "blah"
        assert_empty QUE_LOGGER.messages
      ensure
        Que.log_formatter = nil
      end
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
        Que.logger = QUE_LOGGER
        $level = $message = nil
      end
    end

    it "should just log a generic message if the log formatter raises an error" do
      begin
        Que.log_formatter = proc { |m| raise "Blah!" }

        Que.log event: "blah", source: 4
        assert_equal 1, QUE_LOGGER.messages.count

        message = QUE_LOGGER.messages.first
        assert message.start_with?(
          "Error raised from Que.log_formatter proc: RuntimeError: Blah!"
        )
      ensure
        Que.log_formatter = nil
      end
    end
  end
end
