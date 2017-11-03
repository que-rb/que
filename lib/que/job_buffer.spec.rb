# frozen_string_literal: true

require 'spec_helper'

describe Que::JobBuffer do
  let(:now) { Time.now }
  let(:old) { now - 50 }

  let :job_buffer do
    Que::JobBuffer.new(
      maximum_size: 8,
      minimum_size: 0,
      priorities: [10, 30, 50, nil].shuffle,
    )
  end

  let :job_array do
    [
      {priority: 1, run_at: old, id: 1},
      {priority: 1, run_at: old, id: 2},
      {priority: 1, run_at: now, id: 3},
      {priority: 1, run_at: now, id: 4},
      {priority: 2, run_at: old, id: 5},
      {priority: 2, run_at: old, id: 6},
      {priority: 2, run_at: now, id: 7},
      {priority: 2, run_at: now, id: 8},
    ].map { |sort_key| new_metajob(sort_key) }
  end

  def new_metajob(key)
    key[:queue] ||= ''
    Que::Metajob.new(key)
  end

  describe "during instantiation" do
    it "should raise an error if passed a maximum buffer size less than zero" do
      error = assert_raises(Que::Error) do
        Que::JobBuffer.new(minimum_size: 0, maximum_size: -1, priorities: [10])
      end

      assert_equal "maximum_size for a JobBuffer must be at least zero!", error.message
    end

    it "should raise an error if passed a minimum buffer size less than zero" do
      error = assert_raises(Que::Error) do
        Que::JobBuffer.new(minimum_size: -1, maximum_size: 8, priorities: [10])
      end

      assert_equal "minimum_size for a JobBuffer must be at least zero!", error.message
    end

    it "should raise an error if passed a minimum buffer size larger than its maximum" do
      error = assert_raises(Que::Error) do
        Que::JobBuffer.new(minimum_size: 10, maximum_size: 8, priorities: [10])
      end

      assert_equal "minimum buffer size (10) is greater than the maximum buffer size (8)!", error.message
    end
  end

  describe "jobs_needed?" do
    it "should return true iff the current size is less than the minimum" do
      buffer = Que::JobBuffer.new(minimum_size: 2, maximum_size: 8, priorities: [10])

      assert_equal true, buffer.jobs_needed?
      buffer.push job_array.pop
      assert_equal true, buffer.jobs_needed?
      buffer.push job_array.pop
      assert_equal false, buffer.jobs_needed?
      buffer.push job_array.pop
      assert_equal false, buffer.jobs_needed?
    end
  end

  describe "push" do
    it "should add an item and retain the sort order" do
      ids = []

      job_array.shuffle.each do |job|
        assert_nil job_buffer.push(job)
        ids << job.id
        assert_equal ids.sort, job_buffer.to_a.map(&:id)
      end

      assert_equal job_array, job_buffer.to_a
    end

    it "should be able to add many items at once" do
      assert_nil job_buffer.push(*job_array.shuffle)
      assert_equal job_array, job_buffer.to_a
    end

    describe "when the maximum size has been reached" do
      let :important_values do
        (1..3).map { |id| new_metajob(priority: 0, run_at: old, id: id) }
      end

      before do
        job_buffer.push(*job_array)
      end

      it "should pop the least important jobs and return their pks" do
        assert_equal \
          job_array[7..7],
          job_buffer.push(important_values[0])

        assert_equal \
          job_array[5..6],
          job_buffer.push(*important_values[1..2])

        assert_equal 8, job_buffer.size
      end

      it "should work when passing multiple pks that would pass the maximum" do
        assert_equal \
          job_array.first,
          job_buffer.shift

        assert_equal \
          job_array[7..7],
          job_buffer.push(*important_values[0..1])

        assert_equal 8, job_buffer.size
      end

      # Pushing very low priority jobs shouldn't happen, since we use
      # #accept? to prevent unnecessary locking, but just in case:
      it "should work when the jobs wouldn't make the cut" do
        v = new_metajob(priority: 100, run_at: Time.now, id: 45)
        assert_equal [v], job_buffer.push(v)
        refute_includes job_buffer.to_a, v
        assert_equal 8, job_buffer.size
      end

      it "should reject all jobs when the queue is stopping" do
        job_buffer.stop
        assert_equal(job_array.sort, job_buffer.push(*job_array.shuffle).sort)
      end
    end
  end

  describe "shift" do
    it "should return the lowest item's pk by sort order" do
      job_buffer.push *job_array

      assert_equal job_array[0],    job_buffer.shift
      assert_equal job_array[1..7], job_buffer.to_a

      assert_equal job_array[1],    job_buffer.shift
      assert_equal job_array[2..7], job_buffer.to_a
    end

    it "should block for multiple threads when the queue is empty" do
      job_buffer # Pre-initialize to avoid race conditions.

      threads =
        4.times.map do
          Thread.new do
            Thread.current[:job] = job_buffer.shift
          end
        end

      sleep_until! { threads.all? { |t| t.status == 'sleep' } }
      job_buffer.push *job_array
      sleep_until! { threads.all? { |t| t.status == false } }

      assert_equal \
        job_array[0..3],
        threads.
          map{|t| t[:job]}.
          sort

      assert_equal job_array[4..7], job_buffer.to_a
    end

    it "should respect a priority threshold argument" do
      a = new_metajob(priority: 25, run_at: Time.now, id: 1)
      b = new_metajob(priority: 25, run_at: Time.now, id: 2)
      c = new_metajob(priority:  5, run_at: Time.now, id: 3)

      job_buffer.push(a)
      t = Thread.new { Thread.current[:job] = job_buffer.shift(10) }
      sleep_until! { t.status == 'sleep' }

      job_buffer.push(b)
      sleep_until! { t.status == 'sleep' }

      job_buffer.push(c)
      sleep_until! { t.status == false }

      assert_equal c, t[:job]
    end

    it "when blocked should only return for a request of sufficient priority" do
      job_buffer # Pre-initialize to avoid race conditions.

      # Randomize order in which threads lock.
      threads = [10, 30, 50].shuffle.map do |priority|
        Thread.new do
          Thread.current[:priority] = priority
          Thread.current[:job] = job_buffer.shift(priority)
        end
      end

      sleep_until! { threads.all? { |t| t.status == 'sleep' } }

      threads.sort_by! { |t| t[:priority] }

      value = new_metajob(priority: 25, run_at: Time.now, id: 1)
      job_buffer.push value

      sleep_until! { threads.map(&:status) == ['sleep', 'sleep', false] }

      assert_equal value, threads[2][:job]
    end
  end

  describe "accept?" do
    it "should return the array of sort keys that would be accepted to the queue" do
      # This is a fuzz test, basically, so try bumping this iteration count up
      # when we tweak the accept? logic.
      5.times do
        maximum_size = rand(8) + 1
        job_buffer =
          Que::JobBuffer.new(
            maximum_size: maximum_size,
            minimum_size: 0,
            priorities: [10],
          )

        jobs_that_should_make_it_in = job_array.first(maximum_size)

        job_array_copy = job_array.shuffle

        partition = rand(maximum_size) + 1
        jobs_in_queue = job_array_copy[0...partition]
        jobs_to_test  = job_array_copy[partition..-1]

        assert_nil job_buffer.push(*jobs_in_queue)

        assert_equal(
          (jobs_that_should_make_it_in & jobs_to_test).sort_by{|j| j.job.values_at(:priority, :run_at, :id)},
          job_buffer.accept?(jobs_to_test),
        )
      end
    end

    it "should return an empty array when the queue is stopping" do
      assert_equal job_array, job_buffer.accept?(job_array)
      assert_equal job_array, job_buffer.accept?(job_array)

      job_buffer.stop

      assert_equal [], job_buffer.accept?(job_array)
    end
  end

  describe "buffer_space" do
    it "should return how much space is available in the buffer" do
      job_buffer.push(*job_array.sample(3))
      assert_equal 5, job_buffer.buffer_space
    end
  end

  describe "size" do
    it "should return the current number of items in the queue" do
      job_buffer.push(*job_array.sample(3))
      assert_equal 3, job_buffer.size
    end
  end

  describe "to_a" do
    it "should return a copy of the current items in the queue" do
      jobs = job_array.sample(3)
      job_buffer.push(*jobs)

      assert_equal(
        jobs.sort_by{|j| j.job.values_at(:priority, :run_at, :id)},
        job_buffer.to_a,
      )

      # Make sure that calls produce different array objects.
      refute_equal(job_buffer.to_a.object_id, job_buffer.to_a.object_id)
    end
  end

  describe "stop" do
    it "should return false to waiting workers" do
      job_buffer # Pre-initialize to avoid race conditions.

      threads =
        4.times.map do
          Thread.new do
            Thread.current[:job] = job_buffer.shift
          end
        end

      sleep_until! { threads.all? { |t| t.status == 'sleep' } }
      job_buffer.stop
      sleep_until! { threads.all? { |t| t.status == false } }

      threads.map { |t| assert_equal false, t[:job] }
      10.times { assert_equal false, job_buffer.shift }
    end
  end

  describe "clear" do
    it "should remove and return all items" do
      job_buffer.push *job_array
      assert_equal job_array, job_buffer.clear
      assert_equal [], job_buffer.to_a
    end

    it "should return an empty array if there are no items to clear" do
      assert_equal [], job_buffer.clear
      job_buffer.push *job_array
      assert_equal job_array, job_buffer.clear
      assert_equal [], job_buffer.clear
    end
  end

  describe "stopping?" do
    it "should return true if the job queue is being shut down" do
      refute job_buffer.stopping?
      job_buffer.stop
      assert job_buffer.stopping?
    end
  end
end
