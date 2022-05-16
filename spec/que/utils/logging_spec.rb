# frozen_string_literal: true

require 'spec_helper'

describe Que::Utils::Logging do
  describe "log" do
    it "should record the library and hostname and thread id in JSON" do
      Que.log event: :blah, source: 4
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
      Que.log(event: :blah)
      assert called
      refute_empty QUE_LOGGER.messages
    end

    it "should not raise an error when no logger is present" do
      Que.logger = nil
      assert_nil Que.log(event: :blah)
      assert_empty QUE_LOGGER.messages
    end

    it "should allow the use of a custom log formatter" do
      Que.log_formatter = proc { |data| "Logged event is #{data[:event]}" }
      Que.log event: :my_event
      assert_equal 1, QUE_LOGGER.messages.count
      assert_equal "Logged event is my_event", QUE_LOGGER.messages.first
    end

    it "should not log anything if the logging formatter returns falsey" do
      Que.log_formatter = proc { |data| false }
      Que.log event: :blah
      assert_empty QUE_LOGGER.messages
    end

    it "should use a :level option to set the log level if one exists" do
      begin
        Que.logger = o = Object.new

        def o.method_missing(level, message)
          $level = level
          $message = message
        end

        Que.log event: :thing_happened, message: 'one'
        assert_equal :info, $level
        assert_equal 'one', JSON.load($message)['message']

        Que.log event: :thing_happened, message: 'two', level: 'debug'
        assert_equal :debug, $level
        assert_equal 'two', JSON.load($message)['message']
      ensure
        $level = $message = nil
      end
    end

    it "should just log a generic message if the log formatter raises an error" do
      Que.log_formatter = proc { |m| raise "Blah!" }

      Que.log event: :blah, source: 4
      assert_equal 1, QUE_LOGGER.messages.count

      message = QUE_LOGGER.messages.first
      assert message.start_with?(
        "Error raised from Que.log_formatter proc: RuntimeError: Blah!"
      )
    end
  end

  describe "get_logger" do
    it "should return nil if the logger is nil" do
      Que.logger          = nil
      Que.internal_logger = nil

      assert_nil Que.get_logger
      assert_nil Que.get_logger(internal: true)
    end

    it "should return the logger if it's a non-callable" do
      Que.logger          = 5
      Que.internal_logger = 5

      assert_equal 5, Que.get_logger
      assert_equal 5, Que.get_logger(internal: true)

      Que.logger          = nil
      Que.internal_logger = nil
    end

    it "should return the results of a callable" do
      Que.logger          = proc { 'blah1' }
      Que.internal_logger = proc { 'blah2' }

      assert_equal 'blah1', Que.get_logger
      assert_equal 'blah2', Que.get_logger(internal: true)

      Que.logger          = nil
      Que.internal_logger = nil
    end
  end

  describe "internal_log" do
    def get_messages
      messages = QUE_INTERNAL_LOGGER.messages.map{|m| JSON.parse(m, symbolize_names: true)}
      messages.each do |message|
        assert_in_delta Time.iso8601(message.delete(:t)), Time.now.utc, QueSpec::TIME_SKEW
      end
      messages
    end

    it "should be a no-op if there's no internal_logger set" do
      Que.internal_logger = nil
      assert_nil Que.internal_log(:thing_happened) { raise "Blah!" }
    end

    it "should output whatever's in the block to the internal_logger" do
      Que.internal_log(:thing_happened) { {key: "Blah!"} }
      Que.internal_log(:thing_happened) { {key: "Blah again!"} }

      assert_equal(
        [
          {
            lib: 'que',
            hostname: Socket.gethostname,
            pid: Process.pid,
            thread: Thread.current.object_id,
            internal_event: 'thing_happened',
            key: "Blah!",
          },
          {
            lib: 'que',
            hostname: Socket.gethostname,
            pid: Process.pid,
            thread: Thread.current.object_id,
            internal_event: 'thing_happened',
            key: "Blah again!",
          },
        ],
        get_messages,
      )
    end

    it "when given an object as the second argument should include its object_id" do
      object = Object.new
      Que.internal_log(:thing_happened, object) { {key: "Blah!"} }

      assert_equal(
        [
          {
            lib: 'que',
            hostname: Socket.gethostname,
            pid: Process.pid,
            thread: Thread.current.object_id,
            internal_event: 'thing_happened',
            object_id: object.object_id,
            key: "Blah!",
          },
        ],
        get_messages,
      )
    end

    it "should support assigning a proc as the internal logger" do
      called = false
      Que.internal_logger = proc { called = true; QUE_INTERNAL_LOGGER }
      Que.internal_log(:thing_happened) { {key: "Blah!"} }

      assert called
      assert_equal(
        [
          {
            lib: 'que',
            hostname: Socket.gethostname,
            pid: Process.pid,
            thread: Thread.current.object_id,
            internal_event: 'thing_happened',
            key: "Blah!",
          },
        ],
        get_messages,
      )
    end
  end
end
