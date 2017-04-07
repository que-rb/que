# frozen_string_literal: true

# A thread-safe queue that holds job primary keys in sorted order. Supports
# blocking while waiting for a job to become available, stopping, and only
# returning jobs over a minimum priority.

module Que
  class JobQueue
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
        @array.push(*sort_keys).sort_by! do |sort_key|
          sort_key.values_at(:priority, :run_at, :id)
        end

        # Notify all waiting threads that they can try again to remove a item.
        # TODO: Consider `jobs.length.times { @cv.signal }`?
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
      # Accept the job if there's space available or if it will sort lower than
      # the lowest job currently in the queue.
      sync { space > 0 || sort_key.fetch(:priority) < @array.last.fetch(:priority) }
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
