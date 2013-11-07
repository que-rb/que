require 'spec_helper'

describe Que::Worker do
  class ExceptionJob < Que::Job
    def perform(*args)
      raise "Blah!"
    end
  end

  it "should not be taken out by an error, and keep looking for jobs" do
    ExceptionJob.queue
    Que::Job.queue

    Que::Worker.state = :async
    Que::Worker.wake!
    @worker = Que::Worker.workers.first

    {} until @worker.thread[:state] == :sleeping

    # Job was worked, ExceptionJob remains.
    Que::Job.select_map(:type).should == ['ExceptionJob']
  end

  it "#async? and #up? should return whether Worker is async and whether there are workers running, respectively" do
    Que::Worker.should_not be_async
    Que::Worker.should_not be_up
    Que::Worker.state = :async
    Que::Worker.should be_async
    Que::Worker.should be_up
  end
end
