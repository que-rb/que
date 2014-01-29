# Similar to the standard library's Queue class in terms of synchronizing
# access, but keeps jobs in the order we want to work them. Assumes there's
# many threads competing to retrieve jobs.

module Que
  class JobQueue
    def initialize
      @stop  = false
      @array = []
      @mutex = Mutex.new
      @cv    = ConditionVariable.new
    end

    def push(*jobs)
      jobs.flatten!

      @mutex.synchronize do
        # At some point, for large queue sizes and small numbers of jobs to
        # insert, it may be worth investigating an insertion by binary search.
        @array.push(*jobs).sort_by! { |job| job.values_at(:priority, :run_at, :job_id) }
        @cv.broadcast
      end
    end

    # Looping/ConditionVariable technique borrowed from the rubysl-thread gem.
    def shift(priority = Float::INFINITY)
      loop do
        @mutex.synchronize do
          if @stop
            @cv.signal
            return :stop
          elsif (pk = @array.first) && pk[:priority] <= priority
            item = @array.shift
            @cv.signal
            return item
          else
            @cv.wait(@mutex)
          end
        end
      end
    end

    def count
      @array.count
    end

    def to_a
      @array.dup
    end

    def stop
      @mutex.synchronize do
        @stop = true
        @cv.signal
      end
    end

    def clear
      @mutex.synchronize do
        ids = @array.map { |pk| pk[:job_id] }
        @array.clear
        @cv.signal
        ids
      end
    end
  end
end
