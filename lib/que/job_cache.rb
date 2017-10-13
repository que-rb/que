# frozen_string_literal: true

# A sized thread-safe queue that holds ordered job sort_keys. Supports blocking
# while waiting for a job to become available, only returning jobs over a
# minimum priority, and stopping gracefully.

module Que
  class JobCache
    attr_reader :maximum_size, :minimum_size, :priority_queues

    def initialize(
      maximum_size:,
      minimum_size:,
      priorities:
    )
      @maximum_size = Que.assert(Integer, maximum_size)
      Que.assert(maximum_size >= 0) { "maximum_size for a JobCache must be at least zero!" }

      @minimum_size = Que.assert(Integer, minimum_size)
      Que.assert(minimum_size >= 0) { "minimum_size for a JobCache must be at least zero!" }

      Que.assert(minimum_size <= maximum_size) do
        "minimum queue size (#{minimum_size}) is " \
          "greater than the maximum queue size (#{maximum_size})!"
      end

      @stop    = false
      @array   = []
      @monitor = Monitor.new # TODO: Make this a mutex?

      # Make sure that priority = nil sorts highest.
      @priority_queues = Hash[
        priorities.sort_by{|p| p || Float::INFINITY}.map do |p|
          [p, PriorityQueue.new(priority: p, job_cache: self)]
        end
      ].freeze
    end

    def push(*metajobs)
      Que.internal_log(:job_cache_push, self) do
        {
          maximum_size:  maximum_size,
          ids:           metajobs.map(&:id),
          current_queue: @array,
        }
      end

      sync do
        return metajobs if stopping?

        @array.push(*metajobs).sort!

        # Relying on the hash's contents being sorted, here.
        priority_queues.reverse_each do |_, pq|
          pq.waiting_count.times do
            job = shift_job(pq.priority)
            break if job.nil?
            pq.push(job)
          end
        end

        # If we passed the maximum queue size, drop the lowest sort keys and
        # return their ids to be unlocked.
        overage = -cache_space
        pop(overage) if overage > 0
      end
    end

    def shift(priority = nil)
      queue = priority_queues.fetch(priority) { raise Error, "not a permitted priority! #{priority}" }
      queue.pop
    end

    def shift_job(priority = nil)
      sync do
        if stopping?
          false
        elsif (job = @array.first) && job.priority_sufficient?(priority)
          @array.shift
        end
      end
    end

    def accept?(metajobs)
      return [] if stopping?

      metajobs.sort!

      sync do
        start_index = cache_space
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

    def jobs_needed?
      minimum_size > size
    end

    def waiting_count
      count = 0
      priority_queues.each_value do |pq|
        count += pq.waiting_count
      end
      count
    end

    def jobs_desired
      priority_queues.reverse_each do |priority, pq|
        wc = pq.waiting_count
        wc += cache_space if priority.nil?
        return [wc, priority || MAXIMUM_PRIORITY] if wc > 0
      end

      return [0, MAXIMUM_PRIORITY]
    end

    def cache_space
      sync do
        maximum_size - size
      end
    end

    def size
      sync { @array.size }
    end

    def to_a
      sync { @array.dup }
    end

    def stop
      sync do
        @stop = true
        priority_queues.each_value(&:stop)
      end
    end

    def clear
      sync { pop(size) }
    end

    def stopping?
      sync { !!@stop }
    end

    private

    def pop(count)
      @array.pop(count)
    end

    def sync
      @monitor.synchronize { yield }
    end

    # A queue object dedicated to a specific worker priority. It's basically a
    # Queue object from the standard library, but it's able to reach into the
    # JobCache's cache in order to satisfy a pop.
    class PriorityQueue
      attr_reader :job_cache, :priority

      def initialize(
        job_cache:,
        priority:
      )
        @job_cache = job_cache
        @priority  = priority
        @waiting   = 0
        @stopping  = false
        @items     = [] # Items pending distribution to waiting threads.
        @monitor   = Monitor.new
        @cv        = Monitor::ConditionVariable.new(@monitor)
      end

      def pop
        sync do
          loop do
            return false if @stopping

            if item = @items.pop
              return item
            end

            job = job_cache.shift_job(priority)
            return job unless job.nil? # False means we're stopping.

            @waiting += 1
            @cv.wait
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

      def sync
        @monitor.synchronize { yield }
      end
    end
  end
end
