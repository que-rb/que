require 'spec_helper'

describe Que::Listener do
  it "should exit on its own when informed to stop" do
    listener = Que::Listener.new
    listener.stop
    listener.wait_until_stopped
  end

  it "should register its presence or absence in the que_listeners table upon connecting or disconnecting" do
    listener = Que::Listener.new

    sleep_until { DB[:que_listeners].count == 1 }

    record = DB[:que_listeners].first
    record[:ruby_pid].should      == Process.pid
    record[:ruby_hostname].should == Socket.gethostname
    record[:worker_count].should  == 4
    record[:queue].should         == ''

    listener.stop
    listener.wait_until_stopped

    DB[:que_listeners].count.should be 0
  end
end
