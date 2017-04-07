# frozen_string_literal: true

# A thread-safe queue that holds job primary keys in sorted order. Supports
# blocking while waiting for a job to become available, stopping, and only
# returning jobs over a minimum priority.

module Que
  class JobQueue
    # Don't try to use a binary search input if we're on a Ruby before 2.3.0.
    USE_BINARY_SEARCH = [].respond_to?(:bsearch_index)

    attr_reader :maximum_size

    def initialize(maximum_size: Float::INFINITY)
      @stop         = false
      @array        = []
      @maximum_size = maximum_size

      @monitor = Monitor.new
      @cv      = Monitor::ConditionVariable.new(@monitor)
    end

    def push(*sort_keys)
      sync do
        # At some point, for large queue sizes and small numbers of items to
        # insert, it may be worth investigating an insertion by binary search.

        if USE_BINARY_SEARCH
          sort_keys.each do |key|
            if index = @array.bsearch_index { |k| compare_keys(key, k) }
              @array.insert(index, key)
            else
              @array << key
            end
          end
        else
          @array.push(*sort_keys).sort_by! do |sort_key|
            sort_key.values_at(:priority, :run_at, :id)
          end
        end

        # Notify all waiting threads that they can try again to remove a item.
        # TODO: Consider `sort_keys.length.times { @cv.signal }`?
        @cv.broadcast

        # If we passed the maximum queue size, drop the least important items
        # and return their values.
        overage = size - maximum_size
        pop_ids(overage) if overage > 0
      end
    end

    # Looping/ConditionVariable technique borrowed from the rubysl-thread gem.
    def shift(priority = Float::INFINITY)
      loop do
        sync do
          if @stop
            return
          elsif (sort_key = @array.first) && sort_key.fetch(:priority) <= priority
            return shift_id
          else
            @cv.wait
          end
        end
      end
    end

    def accept?(sort_key)
      # Accept the job if there's space available or if it's more important than
      # the least important item in the queue.
      sync { space > 0 || compare_keys(sort_key, @array.last) }
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
      sync { pop_ids(size) }
    end

    private

    SORT_KEYS = [:priority, :run_at, :id].freeze

    def compare_keys(a, b)
      SORT_KEYS.each do |key|
        a_value = a.fetch(key)
        b_value = b.fetch(key)

        return true  if b_value > a_value
        return false if b_value < a_value
      end

      # Comparing a job's sort key against itself - this shouldn't happen.
      raise Que::Error, "Compared a job's sort key to itself!"
    end

    def shift_id
      @array.shift.fetch(:id)
    end

    def pop_ids(count)
      @array.pop(count).map { |job| job.fetch(:id) }
    end

    def sync(&block)
      @monitor.synchronize(&block)
    end
  end
end
