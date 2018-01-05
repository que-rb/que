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
      sync { @array.push(item) }
    end

    def clear
      sync { @array.pop(@array.size) }
    end

    def to_a
      sync { @array.dup }
    end

    def length
      sync { @array.length }
    end

    private

    def sync(&block)
      @mutex.synchronize(&block)
    end
  end
end
