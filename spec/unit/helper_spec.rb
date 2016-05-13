# frozen_string_literal: true

require 'spec_helper'

describe Que, 'helpers' do
  it "should be able to clear the jobs table" do
    DB[:que_jobs].insert job_class: "Que::Job"
    DB[:que_jobs].count.should be 1
    Que.clear!
    DB[:que_jobs].count.should be 0
  end
end
