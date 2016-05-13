# frozen_string_literal: true

# A thread-safe queue that holds ids for jobs that have been worked. Allows
# appending single/retrieving all ids in a thread-safe fashion.

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
