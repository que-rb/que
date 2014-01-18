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

  it "should clear invalid listeners from the table when connecting" do
    # Note that we assume that the connection we use to register the bogus
    # listener here will be reused by the actual listener below, in order to
    # spec the cleaning of listeners previously registered by the same
    # connection. This will have to be revisited if the behavior of
    # ConnectionPool (our default adapter) is ever changed.
    Que.execute :register_listener, ['', 3, 0, 'blah1']
    DB[:que_listeners].insert :pid           => 0,
                              :ruby_pid      => 0,
                              :ruby_hostname => 'blah2',
                              :worker_count  => 4,
                              :queue         => ''

    DB[:que_listeners].count.should be 2

    pid = DB[:que_listeners].exclude(:pid => 0).get(:pid)

    listener = Que::Listener.new
    sleep_until { DB[:que_listeners].count == 1 }

    record = DB[:que_listeners].first
    record[:pid].should == pid
    record[:ruby_pid].should == Process.pid

    listener.stop
    listener.wait_until_stopped

    DB[:que_listeners].count.should be 0
  end
end
