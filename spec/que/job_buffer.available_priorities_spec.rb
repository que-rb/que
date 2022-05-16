# frozen_string_literal: true

require 'spec_helper'

describe Que::JobBuffer, "available_priorities" do
  class DummyWorker
    attr_reader :thread

    def initialize(priority:, job_buffer:)
      @thread = Thread.new do
        job_buffer.shift(priority)
      end
    end

    def kill
      @thread.kill
    end
  end

  let :worker_priorities do
    [10, 10, 30, 30, 50, 50, nil, nil, nil, nil]
  end

  let(:maximum_size) { 8 }

  let :job_buffer do
    Que::JobBuffer.new(
      maximum_size: maximum_size,
      priorities: worker_priorities.uniq,
    )
  end

  let :dummy_workers do
    worker_priorities.shuffle.map do |priority|
      DummyWorker.new(
        priority: priority,
        job_buffer: job_buffer,
      )
    end
  end

  def fill_buffer(amounts)
    metajobs = []

    amounts.each do |priority, count|
      count.times do
        metajobs << new_metajob(priority: priority)
      end
    end

    job_buffer.push(*metajobs)
  end

  def assert_available(expected)
    sleep_until_equal(expected) { job_buffer.available_priorities }
  end

  def new_metajob(key)
    key[:queue]  ||= ''
    key[:run_at] ||= Time.now
    key[:id]     ||= rand(1_000_000_000)
    Que::Metajob.new(key)
  end

  before do
    sleep_until_equal(dummy_workers.map{"sleep"}) { dummy_workers.map { |w| w.thread.status } }
  end

  after { dummy_workers.each(&:kill) }

  describe "when the job queue is empty and there are free low-priority workers" do
    it "should ask for enough jobs to satisfy all of its unprioritized workers and fill the queue" do
      assert_available(
        10    => 2,
        30    => 2,
        50    => 2,
        32767 => 12,
      )
    end
  end

  describe "when the low-priority workers are all busy" do
    before { fill_buffer(100 => 4) }

    it "should only ask for jobs to fill the buffer" do
      assert_available(
        10    => 2,
        30    => 2,
        50    => 2,
        32767 => 8,
      )
    end
  end

  describe "when the buffer is full and the low-priority workers are busy" do
    before { fill_buffer(100 => 12) }

    it "should only ask for jobs at the higher priority levels" do
      assert_available(
        10 => 2,
        30 => 2,
        50 => 2,
      )
    end
  end

  describe "when the job queue is completely full" do
    before { fill_buffer(5 => 18) }

    it "should ask for zero jobs" do
      assert_available({})
    end
  end

  describe "when the maximum buffer size is zero" do
    let(:maximum_size) { 0 }

    describe "and all the workers are free" do
      it "should not include any buffer space in the available counts" do
        assert_available(
          10    => 2,
          30    => 2,
          50    => 2,
          32767 => 4,
        )
      end
    end

    describe "and the low-priority workers are busy" do
      before { fill_buffer(100 => 4) }

      it "should only ask for jobs at the next priority level" do
        assert_available(
          10    => 2,
          30    => 2,
          50    => 2,
        )
      end
    end

    describe "and all the workers are busy" do
      before { fill_buffer(5 => 10) }

      it "should ask for zero jobs" do
        assert_available({})
      end
    end
  end
end
