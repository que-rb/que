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

      @waiting_count = 0
      @monitor = Monitor.new
      @cv      = Monitor::ConditionVariable.new(@monitor)
    end

    def push(*metajobs)
      Que.internal_log(:job_queue_push, self) do
        {
          maximum_size:  maximum_size,
          sort_keys:     metajobs.map(&:sort_key),
          current_queue: @array,
        }
      end

      sync do
        @array.push(*metajobs).sort!

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
        overage = -space
        pop(overage) if overage > 0
      end
    end

    # Looping/ConditionVariable technique borrowed from the rubysl-thread gem.
    def shift(priority = nil)
      loop do
        sync do
          if stopping?
            return
          elsif (job = @array.first) && job.priority_sufficient?(priority)
            return @array.shift
          else
            if priority.nil?
              @waiting_count += 1
              @cv.wait
              @waiting_count -= 1
            else
              @cv.wait
            end
          end
        end
      end
    end

    def accept?(metajobs)
      metajobs.sort!

      sync do
        start_index = space
        final_index = metajobs.length - 1

        return metajobs if start_index > final_index
        index_to_lose = @array.length - 1

        start_index.upto(final_index) do |index|
          if index_to_lose >= 0 && (metajobs[index] <=> @array[index_to_lose]) < 0
            return metajobs if index == final_index
            index_to_lose -= 1
          else
            return metajobs.slice(0...index)
          end
        end

        []
      end
    end

    def space
      sync do
        maximum_size + @waiting_count - size
      end
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

    def pop(count)
      @array.pop(count)
    end

    def sync(&block)
      @monitor.synchronize(&block)
    end
  end
end
