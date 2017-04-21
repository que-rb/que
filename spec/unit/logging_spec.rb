# frozen_string_literal: true

require 'spec_helper'

describe "Logging" do
  it "should record the library and hostname and thread id in JSON" do
    Que.log event: "blah", source: 4
    assert_equal 1, $logger.messages.count

    message = JSON.load($logger.messages.first)
    assert_equal 'que', message['lib']
    assert_equal Socket.gethostname, message['hostname']
    assert_equal Process.pid, message['pid']
    assert_equal 'blah', message['event']
    assert_equal 4, message['source']
    assert_equal Thread.current.object_id, message['thread']
  end

  it "should allow a callable to be set as the logger" do
    begin
      $logger.messages.clear
      Que.logger = proc { $logger }

      Que::Job.enqueue
      locker = Que::Locker.new
      sleep_until { unprocessed_jobs.empty? }
      locker.stop!

      assert $logger.messages.count > 0
    ensure
      Que.logger = $logger
    end
  end

  it "should not raise an error when no logger is present" do
    begin
      # Make sure we can get through a work cycle without a logger.
      Que.logger = nil

      Que::Job.enqueue
      locker = Que::Locker.new
      sleep_until { unprocessed_jobs.empty? }
      locker.stop!
    ensure
      Que.logger = $logger
    end
  end

  it "should allow the use of a custom log formatter" do
    begin
      Que.log_formatter = proc { |data| "Logged event is #{data[:event]}" }
      Que.log event: 'my_event'
      assert_equal 1, $logger.messages.count
      assert_equal "Logged event is my_event", $logger.messages.first
    ensure
      Que.log_formatter = nil
    end
  end

  it "should not log anything if the logging formatter returns falsey" do
    begin
      Que.log_formatter = proc { |data| false }

      Que.log event: "blah"
      assert_empty $logger.messages
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
      Que.logger = $logger
      $level = $message = nil
    end
  end

  it "should just log a generic message if the log formatter raises an error" do
    begin
      Que.log_formatter = proc { |m| raise "Blah!" }

      Que.log event: "blah", source: 4
      assert_equal 1, $logger.messages.count

      message = $logger.messages.first
      assert message.start_with?(
        "Error raised from Que.log_formatter proc: RuntimeError: Blah!"
      )
    ensure
      Que.log_formatter = nil
    end
  end
end
