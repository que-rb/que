module Que
  class ThreadSafeArray
    def initialize
      @array = []
      @mutex = Mutex.new
    end

    def push(item)
      @mutex.synchronize { @array.push(item) }
    end

    def pop
      @mutex.synchronize { @array.pop }
    end

    def to_a
      @array.dup
    end
  end
end
