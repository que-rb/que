# frozen_string_literal: true

require 'spec_helper'

describe Que::Job, '.run' do
  it "should immediately process the job with the arguments given to it" do
    result = ArgsJob.run 1, 'two', {three: 3}
    assert_instance_of ArgsJob, result
    assert_equal [1, 'two', {three: 3}], result.attrs[:args]

    assert_equal 0, jobs.count
    assert_equal [1, 'two', {three: 3}], $passed_args
  end
end
