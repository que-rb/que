# frozen_string_literal: true

require 'spec_helper'

describe Que::JobQueue do
  let(:now) { Time.now }
  let(:old) { now - 50 }

  let :job_queue do
    Que::JobQueue.new(maximum_size: 8)
  end

  let :job_array do
    [
      {queue: '', priority: 1, run_at: old, id: 1},
      {queue: '', priority: 1, run_at: old, id: 2},
      {queue: '', priority: 1, run_at: now, id: 3},
      {queue: '', priority: 1, run_at: now, id: 4},
      {queue: '', priority: 2, run_at: old, id: 5},
      {queue: '', priority: 2, run_at: old, id: 6},
      {queue: '', priority: 2, run_at: now, id: 7},
      {queue: '', priority: 2, run_at: now, id: 8},
    ]
  end

  describe "push" do
    it "should add an item and retain the sort order" do
      ids = []

      job_array.shuffle.each do |job|
        assert_nil job_queue.push(job)
        ids << job[:id]
        assert_equal ids.sort, job_queue.to_a.map{|j| j[:id]}
      end

      assert_equal job_array, job_queue.to_a
    end

    it "should be able to add many items at once" do
      assert_nil job_queue.push(*job_array.shuffle)
      assert_equal job_array, job_queue.to_a
    end

    describe "when the maximum size has been reached" do
      let :important_values do
        (1..3).map { |id| {queue: '', priority: 0, run_at: old, id: id} }
      end

      before do
        job_queue.push(*job_array)
      end

      it "should pop the least important jobs and return their pks" do
        assert_equal \
          job_array[7..7],
          job_queue.push(important_values[0])

        assert_equal \
          job_array[5..6],
          job_queue.push(*important_values[1..2])

        assert_equal 8, job_queue.size
      end

      it "should work when passing multiple pks that would pass the maximum" do
        assert_equal \
          job_array.first,
          job_queue.shift

        assert_equal \
          job_array[7..7],
          job_queue.push(*important_values[0..1])

        assert_equal 8, job_queue.size
      end

      # Pushing very low priority jobs shouldn't happen, since we use
      # #accept? to prevent unnecessary locking, but just in case:
      it "should work when the jobs wouldn't make the cut" do
        v = {priority: 100, run_at: Time.now, id: 45}
        assert_equal [v], job_queue.push(v)
        refute_includes job_queue.to_a, v
        assert_equal 8, job_queue.size
      end
    end
  end

  describe "shift" do
    it "should return the lowest item's pk by sort order" do
      job_queue.push *job_array

      assert_equal job_array[0],    job_queue.shift
      assert_equal job_array[1..7], job_queue.to_a

      assert_equal job_array[1],    job_queue.shift
      assert_equal job_array[2..7], job_queue.to_a
    end

    it "should block for multiple threads when the queue is empty" do
      job_queue # Pre-initialize to avoid race conditions.

      threads =
        4.times.map do
          Thread.new do
            Thread.current[:job] = job_queue.shift
          end
        end

      sleep_until! { threads.all? { |t| t.status == 'sleep' } }
      job_queue.push *job_array
      sleep_until! { threads.all? { |t| t.status == false } }

      assert_equal \
        job_array[0..3],
        threads.
          map{|t| t[:job]}.
          sort_by{|pk| pk.values_at(:priority, :run_at, :id)}

      assert_equal job_array[4..7], job_queue.to_a
    end

    it "should respect a minimum priority argument" do
      a = {priority: 10, run_at: Time.now, id: 1}
      b = {priority: 10, run_at: Time.now, id: 2}
      c = {priority:  5, run_at: Time.now, id: 3}

      job_queue.push(a)
      t = Thread.new { Thread.current[:job] = job_queue.shift(5) }
      sleep_until! { t.status == 'sleep' }

      job_queue.push(b)
      sleep_until! { t.status == 'sleep' }

      job_queue.push(c)
      sleep_until! { t.status == false }

      assert_equal c, t[:job]
    end

    it "when blocked should only return for a request of sufficient priority" do
      job_queue # Pre-initialize to avoid race conditions.

      # Randomize order in which threads lock.
      threads = [5, 10, 15, 20].shuffle.map do |priority|
        Thread.new do
          Thread.current[:priority] = priority
          Thread.current[:job] = job_queue.shift(priority)
        end
      end

      sleep_until! { threads.all? { |t| t.status == 'sleep' } }

      threads.sort_by! { |t| t[:priority] }

      value = {queue: '', priority: 17, run_at: Time.now, id: 1}
      job_queue.push value

      sleep_until! { threads[3].status == false }
      assert_equal value, threads[3][:job]
      sleep_until! { threads[0..2].all? { |t| t.status == 'sleep' } }
    end
  end

  describe "accept?" do
    it "should return the array of sort keys that would be accepted to the queue" do
      # This is a fuzz test, basically, so try bumping this iteration count up
      # when we tweak the accept? logic.
      5.times do
        maximum_size = rand(8) + 1
        job_queue = Que::JobQueue.new(maximum_size: maximum_size)
        jobs_that_should_make_it_in = job_array.first(maximum_size)

        job_array_copy = job_array.shuffle

        partition = rand(maximum_size) + 1
        jobs_in_queue = job_array_copy[0...partition]
        jobs_to_test  = job_array_copy[partition..-1]

        assert_nil job_queue.push(*jobs_in_queue)

        assert_equal(
          (jobs_that_should_make_it_in & jobs_to_test).sort_by{|k| k.values_at(:priority, :run_at, :id)},
          job_queue.accept?(jobs_to_test),
        )
      end
    end
  end

  describe "space" do
    it "should return how much space is available in the queue" do
      job_queue.push(*job_array.sample(3))
      assert_equal 5, job_queue.space
    end
  end

  describe "size" do
    it "should return the current number of items in the queue" do
      job_queue.push(*job_array.sample(3))
      assert_equal 3, job_queue.size
    end
  end

  describe "to_a" do
    it "should return a copy of the current items in the queue" do
      jobs = job_array.sample(3)
      job_queue.push(*jobs)

      assert_equal(
        jobs.sort_by{|j| j.values_at(:priority, :run_at, :id)},
        job_queue.to_a,
      )

      # Make sure that calls produce different array objects.
      refute_equal(job_queue.to_a.object_id, job_queue.to_a.object_id)
    end
  end

  describe "stop" do
    it "should return nil to waiting workers" do
      job_queue # Pre-initialize to avoid race conditions.

      threads =
        4.times.map do
          Thread.new do
            Thread.current[:job] = job_queue.shift
          end
        end

      sleep_until! { threads.all? { |t| t.status == 'sleep' } }
      job_queue.stop
      sleep_until! { threads.all? { |t| t.status == false } }

      threads.map { |t| assert_nil t[:job] }
      10.times { assert_nil job_queue.shift }
    end
  end

  describe "clear" do
    it "should remove and return all items" do
      job_queue.push *job_array
      assert_equal job_array, job_queue.clear
      assert_equal [], job_queue.to_a
    end

    it "should return an empty array if there are no items to clear" do
      assert_equal [], job_queue.clear
      job_queue.push *job_array
      assert_equal job_array, job_queue.clear
      assert_equal [], job_queue.clear
    end
  end

  describe "stopping?" do
    it "should return true if the job queue is being shut down" do
      refute job_queue.stopping?
      job_queue.stop
      assert job_queue.stopping?
    end
  end
end
