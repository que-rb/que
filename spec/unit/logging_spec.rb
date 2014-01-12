require 'spec_helper'

describe "Logging" do
  it "by default should record the library and thread id in JSON" do
    Que.log :event => "blah", :source => 4
    $logger.messages.count.should be 1

    message = JSON.load($logger.messages.first)
    message['lib'].should == 'que'
    message['event'].should == 'blah'
    message['source'].should == 4
    message['thread'].should == Thread.current.object_id
  end

  it "should not raise an error when no logger is present" do
    begin
      Que.logger = nil

      Que::Job.queue
      worker = Que::Worker.new
      sleep_until { worker.sleeping? }

      DB[:que_jobs].should be_empty

      worker.stop
      worker.wait_until_stopped
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
