# frozen_string_literal: true

require 'spec_helper'

describe "Que using a bare PG connection" do
  it_behaves_like "a Que adapter"

  it "should synchronize access to that connection" do
    lock   = Que.adapter.lock
    q1, q2 = Queue.new, Queue.new

    thread1 = Thread.new do
      Que.adapter.checkout do
        q1.push nil
        q2.pop
      end
    end

    q1.pop

    thread2 = Thread.new do
      Que.adapter.checkout do
        q1.push nil
        q2.pop
      end
    end

    sleep_until { thread2.status == 'sleep' }

    thread1.should be_alive
    thread2.should be_alive

    lock.send(:instance_variable_get, :@mon_owner).should == thread1
    q2.push nil
    q1.pop
    lock.send(:instance_variable_get, :@mon_owner).should == thread2
    q2.push nil
    thread1.join
    thread2.join
  end
end
