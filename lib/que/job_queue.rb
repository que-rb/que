# A thread-safe queue that holds job primary keys in sorted order.

module Que
  class JobQueue
    attr_reader :maximum_size

    def initialize(options = {})
      @stop         = false
      @array        = []
      @maximum_size = options[:maximum_size] || Float::INFINITY

      @mutex = Mutex.new
      @cv    = ConditionVariable.new
    end

    def push(*jobs)
      @mutex.synchronize do
        # At some point, for large queue sizes and small numbers of items to
        # insert, it may be worth investigating an insertion by binary search.
        @array.push(*jobs).sort!

        # Notify all waiting threads that they can try again to remove a item.
        @cv.broadcast

        # If we passed the maximum queue size, drop the least important items
        # and return their values.
        @array.pop(@array.size - @maximum_size) if @maximum_size < @array.size
      end
    end

    # Looping/ConditionVariable technique borrowed from the rubysl-thread gem.
    def shift(priority = Float::INFINITY)
      loop do
        @mutex.synchronize do
          if @stop
            return
          elsif (pk = @array.first) && pk[1] <= priority
            return @array.shift
          else
            @cv.wait(@mutex)
          end
        end
      end
    end

    def accept?(pk)
      # Accept the pk if there's space available or if it will sort lower than
      # the lowest pk currently in the queue.
      @mutex.synchronize { @array.size < @maximum_size || (pk <=> @array[-1]) == -1 }
    end

    def space
      @mutex.synchronize { @maximum_size - @array.size }
    end

    def size
      @mutex.synchronize { @array.size }
    end

    def to_a
      @mutex.synchronize { @array.dup }
    end

    def stop
      @mutex.synchronize do
        @stop = true
        @cv.broadcast
      end
    end

    def clear
      @mutex.synchronize { @array.pop(@array.size) }
    end
  end
end
