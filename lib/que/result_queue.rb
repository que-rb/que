# A simple, thread-safe queue. Similar to the standard library's Queue class,
# but we can dequeue all items at once and doing so won't block when empty.

module Que
  class ResultQueue
    def initialize
      @array = []
      @mutex = Mutex.new
    end

    def push(item)
      @mutex.synchronize { @array.push(item) }
    end

    def clear
      @mutex.synchronize { @array.pop(@array.size) }
    end

    def to_a
      @array.dup
    end
  end
end
