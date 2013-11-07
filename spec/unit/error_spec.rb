require 'spec_helper'

describe "Que::Job error handling" do
  class ErrorJob < Que::Job
    def perform(*args)
      raise "Boo!"
    end
  end

  it "should increment the error_count, persist the error message and reschedule the job" do
    ErrorJob.queue

    proc { Que::Job.work }.should raise_error RuntimeError, "Boo!"
    Que::Job.count.should be 1

    job = Que::Job.first
    data = JSON.load(job.data)
    data['error_count'].should be 1
    data['error_message'].should =~ /Boo!/
    job.run_at.should be_within(1).of Time.now + 4
  end

  it "should reschedule jobs with exponentially increasing times" do
    ErrorJob.queue
    Que::Job.dataset.update :data => JSON.dump(:error_count => 5)

    proc { Que::Job.work }.should raise_error RuntimeError, "Boo!"
    Que::Job.count.should be 1

    job = Que::Job.first
    data = JSON.load(job.data)
    data['error_count'].should be 6
    data['error_message'].should =~ /Boo!/
    job.run_at.should be_within(1).of Time.now + 1299
  end

  it "should handle errors from jobs that cannot be deserialized" do
    DB[:jobs].insert :type => 'NonexistentJob', :priority => 1
    proc { Que::Job.work }.should raise_error NameError, /uninitialized constant NonexistentJob/

    job = DB[:jobs].first
    JSON.load(job[:data])['error_count'].should be 1
    job[:run_at].should be_within(1).of Time.now + 4
  end
end
