require 'spec_helper'

describe Que::Job do
  it "should sort based on priority, run_at, and job_id, in that order" do
    older = Time.now - 50
    newer = Time.now

    array = [
      Que::Job.new(:priority => 1, :run_at => older, :job_id => 1, :args => '[]'),
      Que::Job.new(:priority => 1, :run_at => older, :job_id => 2, :args => '[]'),
      Que::Job.new(:priority => 1, :run_at => newer, :job_id => 1, :args => '[]'),
      Que::Job.new(:priority => 1, :run_at => newer, :job_id => 2, :args => '[]'),
      Que::Job.new(:priority => 2, :run_at => older, :job_id => 1, :args => '[]'),
      Que::Job.new(:priority => 2, :run_at => older, :job_id => 2, :args => '[]'),
      Que::Job.new(:priority => 2, :run_at => newer, :job_id => 1, :args => '[]'),
      Que::Job.new(:priority => 2, :run_at => newer, :job_id => 2, :args => '[]')
    ]

    array.shuffle.sort.should == array
  end
end
