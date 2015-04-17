require 'spec_helper'

describe "Logging" do
  it "by default should record the library and hostname and thread id in JSON" do
    Que.log event: "blah", source: 4
    $logger.messages.count.should be 1

    message = JSON.load($logger.messages.first)
    message['lib'].should == 'que'
    message['hostname'].should == Socket.gethostname
    message['pid'].should == Process.pid
    message['event'].should == 'blah'
    message['source'].should == 4
    message['thread'].should == Thread.current.object_id
  end

  it "should allow a callable to be set as the logger" do
    begin
      $logger.messages.clear
      Que.logger = proc { $logger }

      Que::Job.enqueue
      locker = Que::Locker.new
      sleep_until { DB[:que_jobs].empty? }
      locker.stop

      $logger.messages.count.should be > 0
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
      sleep_until { DB[:que_jobs].empty? }
      locker.stop
    ensure
      Que.logger = $logger
    end
  end

  it "should allow the use of a custom log formatter" do
    begin
      Que.log_formatter = proc { |data| "Logged event is #{data[:event]}" }
      Que.log event: 'my_event'
      $logger.messages.count.should be 1
      $logger.messages.first.should == "Logged event is my_event"
    ensure
      Que.log_formatter = nil
    end
  end

  it "should not log anything if the logging formatter returns falsey" do
    begin
      Que.log_formatter = proc { |data| false }

      Que.log event: "blah"
      $logger.messages.should be_empty
    ensure
      Que.log_formatter = nil
    end
  end

  it "should use a :level option to set the log level if one exists, or default to info" do
    begin
      Que.logger = o = Object.new

      def o.method_missing(level, message)
        $level = level
        $message = message
      end

      Que.log message: 'one'
      $level.should == :info
      JSON.load($message)['message'].should == 'one'

      Que.log message: 'two', level: 'debug'
      $level.should == :debug
      JSON.load($message)['message'].should == 'two'
    ensure
      Que.logger = $logger
      $level = $message = nil
    end
  end

  it "should just log a generic message if the log formatter raises an error" do
    begin
      Que.log_formatter = proc { |m| raise "Blah!" }

      Que.log event: "blah", source: 4
      $logger.messages.count.should be 1

      message = $logger.messages.first
      message.should start_with "Error raised from Que.log_formatter proc: RuntimeError: Blah!"
    ensure
      Que.log_formatter = nil
    end
  end
end
