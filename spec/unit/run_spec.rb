# frozen_string_literal: true

require 'spec_helper'

describe Que::Job, '.run' do
  it "should immediately process the job with the arguments given to it" do
    result = ArgsJob.run 1, 'two', {three: 3}
    result.should be_an_instance_of ArgsJob
    result.attrs[:args].should == [1, 'two', {three: 3}]

    DB[:que_jobs].count.should be 0
    $passed_args.should == [1, 'two', {three: 3}]
  end
end
