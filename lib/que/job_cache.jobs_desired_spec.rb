# frozen_string_literal: true

require 'spec_helper'

describe Que::JobCache do
  class DummyWorker
    attr_reader :thread

    def initialize(priority:, job_cache:)
      @thread = Thread.new do
        job_cache.shift(priority)
      end
    end

    def kill
      @thread.kill
    end
  end

  def new_metajob(key)
    key[:queue]  ||= ''
    key[:run_at] ||= Time.now
    key[:id]     ||= rand(1_000_000_000)
    Que::Metajob.new(key)
  end

  describe "jobs_desired" do
    let :worker_priorities do
      [10, 10, 30, 30, 50, 50, nil, nil, nil, nil]
    end

    let(:maximum_size) { 8 }
    let(:minimum_size) { 2 }

    let :job_cache do
      Que::JobCache.new(
        maximum_size: maximum_size,
        minimum_size: minimum_size,
        priorities: worker_priorities.uniq,
      )
    end

    let :dummy_workers do
      worker_priorities.shuffle.map do |priority|
        DummyWorker.new(
          priority: priority,
          job_cache: job_cache,
        )
      end
    end

    before do
      sleep_until { dummy_workers.all? { |w| w.thread.status == 'sleep' } }
    end

    after { dummy_workers.each(&:kill) }

    def fill_cache(amounts)
      metajobs = []

      amounts.each do |priority, count|
        count.times do
          metajobs << new_metajob(priority: priority)
        end
      end

      job_cache.push(*metajobs)
    end

    def assert_desired(expected)
      actual = nil
      sleep_until!(0.5) do
        actual = job_cache.jobs_desired
        actual == expected
      end
    rescue
      assert_equal expected, actual # Better error message.
    end

    describe "when the job queue is empty and there are unprioritized workers" do
      it "should ask for enough jobs to satisfy all of its unprioritized workers and fill the queue" do
        assert_desired [12, 32767]
      end
    end

    describe "when the unprioritized workers are all busy" do
      before do
        fill_cache(100 => 4)
      end

      it "should only ask for jobs to fill the cache" do
        assert_desired [8, 32767]
      end
    end

    describe "when the job queue is completely full" do
      before do
        fill_cache(5 => 18)
      end

      it "should ask for zero jobs" do
        assert_desired [0, 32767]
      end
    end
  end
end
