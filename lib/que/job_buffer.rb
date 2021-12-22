# frozen_string_literal: true

# A sized thread-safe queue that holds ordered job sort_keys. Supports blocking
# while waiting for a job to become available, only returning jobs over a
# minimum priority, and stopping gracefully.

module Que
  class JobBuffer
    attr_reader :maximum_size, :minimum_size, :priority_queues

    # Since we use a mutex, which is not reentrant, we have to be a little
    # careful to not call a method that locks the mutex when we've already
    # locked it. So, as a general rule, public methods handle locking the mutex
    # when necessary, while private methods handle the actual underlying data
    # changes. This lets us reuse those private methods without running into
    # locking issues.

    def initialize(
      maximum_size:,
      minimum_size:,
      priorities:
    )
      @maximum_size = Que.assert(Integer, maximum_size)
      Que.assert(maximum_size >= 0) { "maximum_size for a JobBuffer must be at least zero!" }

      @minimum_size = Que.assert(Integer, minimum_size)
      Que.assert(minimum_size >= 0) { "minimum_size for a JobBuffer must be at least zero!" }

      Que.assert(minimum_size <= maximum_size) do
        "minimum buffer size (#{minimum_size}) is " \
          "greater than the maximum buffer size (#{maximum_size})!"
      end

      @stop  = false
      @array = []
      @mutex = Mutex.new

      @priority_queues = Hash[
        # Make sure that priority = nil sorts highest.
        priorities.sort_by{|p| p || MAXIMUM_PRIORITY}.map do |p|
          [p, PriorityQueue.new(priority: p, job_buffer: self)]
        end
      ].freeze
    end

    def push(*metajobs)
      Que.internal_log(:job_buffer_push, self) do
        {
          maximum_size:  maximum_size,
          ids:           metajobs.map(&:id),
          current_queue: to_a,
        }
      end

      sync do
        return metajobs if _stopping?

        @array.concat(metajobs).sort!

        # Relying on the hash's contents being sorted, here.
        priority_queues.reverse_each do |_, pq|
          pq.waiting_count.times do
            job = _shift_job(pq.priority)
            break if job.nil? # False would mean we're stopping.
            pq.push(job)
          end
        end

        # If we passed the maximum buffer size, drop the lowest sort keys and
        # return their ids to be unlocked.
        overage = -_buffer_space
        pop(overage) if overage > 0
      end
    end

    def shift(priority = nil)
      queue = priority_queues.fetch(priority) { raise Error, "not a permitted priority! #{priority}" }
      queue.pop || shift_job(priority)
    end

    def shift_job(priority = nil)
      sync { _shift_job(priority) }
    end

    def accept?(metajobs)
      metajobs.sort!

      sync do
        return [] if _stopping?

        start_index = _buffer_space
        final_index = metajobs.length - 1

        return metajobs if start_index > final_index
        index_to_lose = @array.length - 1

        start_index.upto(final_index) do |index|
          if index_to_lose >= 0 && (metajobs[index] <=> @array[index_to_lose]) < 0
            return metajobs if index == final_index
            index_to_lose -= 1
          else
            return metajobs.slice(0...index)
          end
        end

        []
      end
    end

    def waiting_count
      count = 0
      priority_queues.each_value do |pq|
        count += pq.waiting_count
      end
      count
    end

    def available_priorities
      hash = {}
      lowest_priority = true

      priority_queues.reverse_each do |priority, pq|
        count = pq.waiting_count

        if lowest_priority
          count += buffer_space
          lowest_priority = false
        end

        hash[priority || MAXIMUM_PRIORITY] = count if count > 0
      end

      hash
    end

    def buffer_space
      sync { _buffer_space }
    end

    def size
      sync { _size }
    end

    def to_a
      sync { @array.dup }
    end

    def stop
      sync { @stop = true }
      priority_queues.each_value(&:stop)
    end

    def clear
      sync { pop(_size) }
    end

    def stopping?
      sync { _stopping? }
    end

    def job_available?(priority)
      (job = @array.first) && job.priority_sufficient?(priority)
    end

    private

    def _buffer_space
      maximum_size - _size
    end

    def pop(count)
      @array.pop(count)
    end

    def _shift_job(priority)
      if _stopping?
        false
      elsif (job = @array.first) && job.priority_sufficient?(priority)
        @array.shift
      end
    end

    def _size
      @array.size
    end

    def _stopping?
      !!@stop
    end

    def sync(&block)
      @mutex.synchronize(&block)
    end

    # A queue object dedicated to a specific worker priority. It's basically a
    # Queue object from the standard library, but it's able to reach into the
    # JobBuffer's buffer in order to satisfy a pop.
    class PriorityQueue
      attr_reader :job_buffer, :priority, :mutex

      def initialize(
        job_buffer:,
        priority:
      )
        @job_buffer = job_buffer
        @priority   = priority
        @waiting    = 0
        @stopping   = false
        @items      = [] # Items pending distribution to waiting threads.
        @mutex      = Mutex.new
        @cv         = ConditionVariable.new
      end

      def pop
        sync do
          loop do
            if @stopping
              return false
            elsif item = @items.pop
              return item
            elsif job_buffer.job_available?(priority)
              return false
            end

            @waiting += 1
            @cv.wait(mutex)
            @waiting -= 1
          end
        end
      end

      def push(item)
        sync do
          Que.assert(waiting_count > 0)
          @items << item
          @cv.signal
        end
      end

      def stop
        sync do
          @stopping = true
          @cv.broadcast
        end
      end

      def waiting_count
        @waiting
      end

      private

      def sync(&block)
        mutex.synchronize(&block)
      end
    end
  end
end
