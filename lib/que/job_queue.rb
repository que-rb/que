# A thread-safe queue (one publisher, many subscribers) to hold and distribute
# primary keys for locked jobs. Similar to the Queue class in the standard
# library, but understands things like job priorities and stopping.

module Que
  class JobQueue
    def initialize(max)
      @max   = max
      @stop  = false
      @array = []

      @mutex = Mutex.new
      @cv    = ConditionVariable.new
    end

    def push(*jobs)
      @mutex.synchronize do
        # At some point, for large queue sizes and small numbers of jobs to
        # insert, it may be worth investigating an insertion by binary search.
        @array.push(*jobs.flatten).sort_by! { |job| job.values_at(:priority, :run_at, :job_id) }

        # Notify all waiting threads that they can try again to remove a job.
        @cv.broadcast

        # If we passed the maximum queue size, drop the least important jobs
        # and return their ids to be unlocked.
        dequeue(size - @max) if @max < size
      end
    end

    # Looping/ConditionVariable technique borrowed from the rubysl-thread gem.
    def shift(priority = Float::INFINITY)
      loop do
        @mutex.synchronize do
          if @stop
            return :stop
          elsif (pk = @array.first) && pk[:priority] <= priority
            return @array.shift
          else
            @cv.wait(@mutex)
          end
        end
      end
    end

    def accept?(pk)
      @mutex.synchronize { size < @max || pk[:priority] < @array[-1][:priority] }
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
      @mutex.synchronize { dequeue(size) }
    end

    private

    def dequeue(number)
      @array.pop(number).map { |pk| pk[:job_id] }
    end
  end
end
