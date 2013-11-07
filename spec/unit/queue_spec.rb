require 'spec_helper'

describe "Que::Job.queue" do
  it "should create a job in the DB" do
    Que::Job.queue :param1 => 4, :param2 => 'ferret', :param3 => false
    Que::Job.count.should == 1

    job = Que::Job.first
    job.type.should == 'Que::Job'
    job.run_at.should be_within(1).of Time.now
    job.priority.should be 5 # Defaults to lowest priority.
    JSON.load(job.args).should == [{'param1' => 4, 'param2' => 'ferret', 'param3' => false}]
  end

  it "should accept a :run_at argument" do
    time = Time.at(Time.now.to_i)
    Que::Job.queue :user_id => 4, :test_number => 8, :run_at => time

    Que::Job.count.should == 1
    job = Que::Job.first
    job.type.should == 'Que::Job'
    job.run_at.should == time
    job.priority.should == 5
    JSON.load(job.args).should == [{'user_id' => 4, 'test_number' => 8}]
  end

  it "should accept a :priority argument" do
    Que::Job.queue :user_id => 4, :test_number => 8, :priority => 1

    Que::Job.count.should == 1
    job = Que::Job.first
    job.type.should == 'Que::Job'
    job.run_at.should be_within(1).of Time.now
    job.priority.should be 1
    JSON.load(job.args).should == [{'user_id' => 4, 'test_number' => 8}]
  end

  it "should respect a default_priority for the class" do
    class TestPriorityJob < Que::Job
      @default_priority = 2
    end

    TestPriorityJob.queue :user_id => 4, :test_number => 8

    Que::Job.count.should == 1
    job = Que::Job.first
    job.type.should == 'TestPriorityJob'
    job.run_at.should be_within(1).of Time.now
    job.priority.should be 2
    JSON.load(job.args).should == [{'user_id' => 4, 'test_number' => 8}]
  end

  it "should let a :priority option override a default_priority for the class" do
    class OtherTestPriorityJob < Que::Job
      @default_priority = 2
    end

    OtherTestPriorityJob.queue :user_id => 4, :test_number => 8, :priority => 4

    Que::Job.count.should == 1
    job = Que::Job.first
    job.type.should == 'OtherTestPriorityJob'
    job.run_at.should be_within(1).of Time.now
    job.priority.should be 4
    JSON.load(job.args).should == [{'user_id' => 4, 'test_number' => 8}]
  end
end
