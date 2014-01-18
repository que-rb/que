# A simple, thread-safe queue. Like the standard library's Queue class, but
# when empty it just returns nil instead of blocking until there's something.

module Que
  class ResultQueue
    def initialize
      @array = []
      @mutex = Mutex.new
    end

    def push(item)
      @mutex.synchronize { @array.push(item) }
    end

    def shift
      @mutex.synchronize { @array.shift }
    end

    def to_a
      @array.dup
    end
  end
end
