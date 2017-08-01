# frozen_string_literal: true

# A sized thread-safe queue that holds ordered job sort_keys. Supports blocking
# while waiting for a job to become available, only returning jobs over a
# minimum priority, and stopping gracefully.

module Que
  class JobQueue
    attr_reader :maximum_size

    def initialize(maximum_size:)
      @stop         = false
      @array        = []
      @maximum_size = Que.assert(Integer, maximum_size)
      Que.assert(maximum_size > 0)

      @monitor = Monitor.new
      @cv      = Monitor::ConditionVariable.new(@monitor)
    end

    def push(*sort_keys)
      Que.internal_log(:job_queue_push, self) do
        {
          maximum_size:  maximum_size,
          sort_keys:     sort_keys,
          current_queue: @array,
        }
      end

      sync do
        sort_keys!(@array.push(*sort_keys))

        # Notify all waiting threads that they can try again to remove a item.
        # We could try to only wake up a subset of the waiting threads, to avoid
        # contention when there are many sleeping threads, but not all
        # threads/workers will be interested in all jobs (some have a minimum
        # priority they care about), so how do we notify only the ones with the
        # an appropriate priority threshold? Seems possible, but it would
        # require a custom Monitor/ConditionVariable implementation.
        @cv.broadcast

        # If we passed the maximum queue size, drop the lowest sort keys and
        # return their ids to be unlocked.
        overage = size - maximum_size
        pop(overage) if overage > 0
      end
    end

    # Looping/ConditionVariable technique borrowed from the rubysl-thread gem.
    def shift(priority = Float::INFINITY)
      loop do
        sync do
          if stopping?
            return
          elsif (key = @array.first) && key.fetch(:priority) <= priority
            return @array.shift
          else
            @cv.wait
          end
        end
      end
    end

    def accept?(sort_keys)
      sort_keys!(sort_keys)

      sync do
        start_index = space
        final_index = sort_keys.length - 1

        return sort_keys if start_index > final_index
        index_to_lose = @array.length - 1

        start_index.upto(final_index) do |index|
          if index_to_lose >= 0 && compare_keys(sort_keys[index], @array[index_to_lose])
            return sort_keys if index == final_index
            index_to_lose -= 1
          else
            return sort_keys.slice(0...index)
          end
        end

        []
      end
    end

    def space
      sync { maximum_size - size }
    end

    def size
      sync { @array.size }
    end

    def to_a
      sync { @array.dup }
    end

    def stop
      sync { @stop = true; @cv.broadcast }
    end

    def clear
      sync { pop(size) }
    end

    def stopping?
      sync { !!@stop }
    end

    private

    def sort_keys!(keys)
      # Benchmarked this out of curiosity, and turns out that this sort_by is
      # faster (and triggers fewer GC cycles) than using sort! and passing each
      # pair to compare_keys below.
      keys.sort_by! { |key| key.values_at(:priority, :run_at, :id) }
    end

    SORT_KEYS = [:priority, :run_at, :id].freeze

    # Given two sort keys a and b, returns true if a < b and false if a > b.
    # Throws an error if they're the same - that shouldn't happen.
    def compare_keys(a, b)
      SORT_KEYS.each do |key|
        a_value = a.fetch(key)
        b_value = b.fetch(key)

        return true  if a_value < b_value
        return false if a_value > b_value
      end

      # Comparing a job's sort key against itself - this shouldn't happen.
      raise Error, "Compared a job's sort key to itself!"
    end

    def pop(count)
      @array.pop(count)
    end

    def sync(&block)
      @monitor.synchronize(&block)
    end
  end
end
