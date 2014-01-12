require 'spec_helper'

describe "Logging" do
  it "by default should record the source library and process pid and time in a parseable format" do
    Que.log :event => "blah", :source => 4
    $logger.messages.count.should be 1

    message = JSON.load($logger.messages.first)
    message['lib'].should == 'que'
    message['event'].should == 'blah'
    message['source'].should == 4
    message['pid'].should == Process.pid
    Time.parse(message['time']).should be_within(3).of Time.now
  end

  it "should be easy for job code to do" do
    class LoggingJobA < Que::Job
      def run
        log "message!"
      end
    end

    class LoggingJobB < Que::Job
      def run
        log :param1 => "my_param"
      end
    end

    LoggingJobA.queue
    LoggingJobB.queue

    Que::Job.work
    Que::Job.work

    $logger.messages.count.should be 2
    m1, m2 = $logger.messages.map { |m| JSON.load(m) }

    m1['worker'].should == Thread.current.object_id
    m1['message'].should == "message!"

    m2['worker'].should == Thread.current.object_id
    m2['message']['param1'].should == 'my_param'
  end

  it "should not raise an error when no logger is present" do
    begin
      Que.logger = nil

      Que::Job.queue
      worker = Que::Worker.new
      sleep_until { worker.sleeping? }

      DB[:que_jobs].should be_empty

      worker.thread.kill
      worker.thread.join
    ensure
      Que.logger = $logger
    end
  end

  it "should allow the use of a custom log formatter" do
    begin
      Que.log_formatter = proc { |data| "Logged event is #{data[:event]}" }
      Que.log :event => 'my_event'
      $logger.messages.count.should be 1
      $logger.messages.first.should == "Logged event is my_event"
    ensure
      Que.log_formatter = nil
    end
  end

  it "should not log anything if the logging formatter returns falsey" do
    begin
      Que.log_formatter = proc { |data| false }

      Que.log :event => "blah"
      $logger.messages.should be_empty
    ensure
      Que.log_formatter = nil
    end
  end
end
