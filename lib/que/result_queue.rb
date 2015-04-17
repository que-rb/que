# A thread-safe queue that holds ids for jobs that have been worked, and
# allows retrieving all of its values in a non-blocking, thread-safe fashion.

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
  end
end
