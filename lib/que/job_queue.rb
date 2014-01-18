# Similar to the standard library's Queue class in terms of synchronizing
# access, but keeps jobs in the order we want to work them. Also silently
# discards the least important jobs when the queue reaches a maximum preset.

# Assumes there may be many threads blocking on retrieving a job, and only one
# thread that ever needs to insert one.

module Que
  class JobQueue
    def initialize(max = nil)
      @array = []
      @max   = max
      @mutex = Mutex.new
      @cv    = ConditionVariable.new
    end

    def push(*items)
      items.flatten!

      @mutex.synchronize do
        # At some point, for large queue sizes and small numbers of items to
        # insert, it may be worth investigating an insertion by binary search.
        @array.push(*items).sort!

        if @max && (excess = @array.count - @max) > 0
          @array.pop(excess)
        end

        @cv.signal
      end
    end

    # Implementation borrowed from the rubysl-thread gem.
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
