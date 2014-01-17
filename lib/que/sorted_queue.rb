# Similar to Ruby's Queue class in terms of synchronizing access, but holds
# jobs in the order we'll want to work them and silently discards the least
# important when the queue reaches a maximum preset.

module Que
  class SortedQueue
    def initialize(max = nil)
      @array = []
      @max   = max
      @mutex = Mutex.new
      @cv    = ConditionVariable.new
    end

    def insert(*items)
      items.flatten!

      @mutex.synchronize do
        @array.push(*items).sort!

        if @max && (excess = @array.count - @max) > 0
          @array.pop(excess)
        end

        @cv.signal
      end
    end

    def shift
      loop do
        @mutex.synchronize do
          if @array.empty?
            @cv.wait(@mutex)
          else
            item = @array.shift
            @cv.signal
            return item
          end
        end
      end
    end

    def to_a
      @array.dup
    end
  end
end
