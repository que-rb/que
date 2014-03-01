# A thread-safe queue that holds job primary keys in sorted order.

module Que
  class JobQueue
    def initialize(options = {})
      @max   = options[:maximum_size] || Float::INFINITY
      @stop  = false
      @array = []

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
        @array.pop(size - @max) if @max < size
      end
    end

    # Looping/ConditionVariable technique borrowed from the rubysl-thread gem.
    def shift(priority = Float::INFINITY)
      loop do
        @mutex.synchronize do
          if @stop
            return
          elsif (pk = @array.first) && pk.first <= priority
            return @array.shift
          else
            @cv.wait(@mutex)
          end
        end
      end
    end

    def accept?(pk)
      @mutex.synchronize { size < @max || pk.first < @array[-1].first }
    end

    def space
      @max - size
    end

    def size
      @array.size
    end

    def to_a
      @array.dup
    end

    def stop
      @mutex.synchronize do
        @stop = true
        @cv.broadcast
      end
    end

    def clear
      @mutex.synchronize { @array.pop(size) }
    end
  end
end
