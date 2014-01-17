require 'spec_helper'

describe Que::Worker do
  before do
    @job_queue    = Que::SortedQueue.new
    @result_queue = Que::ThreadSafeArray.new

    @worker = Que::Worker.new :job_queue    => @job_queue,
                              :result_queue => @result_queue
  end

  it "should repeatedly work jobs that are passed to it via its job_queue, ordered correctly" do
    begin
      $results = []

      class WorkerJob < Que::Job
        def run(number)
          $results << number
        end
      end

      jobs = [1, 2, 3].map do |i|
        WorkerJob.new :priority => i,
                      :run_at   => Time.now,
                      :job_id   => i,
                      :args     => "[#{i}]"
      end

      jobs.shuffle!

      @job_queue.insert(jobs)
      sleep_until { $results.count == 3 }

      $results.should == [1, 2, 3]
      @result_queue.to_a.should == [1, 2, 3]
    ensure
      $results = nil
    end
  end
end
