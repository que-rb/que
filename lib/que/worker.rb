require 'monitor'

module Que
  class Worker
    # Each worker has a thread that does the actual work of running jobs.
    # Since both the worker's thread and whatever thread is managing the
    # worker are capable of affecting the state of the worker's thread, we
    # need to synchronize access to it.

    include MonitorMixin

    attr_reader :thread

    def initialize
      super # For MonitorMixin.

      # We have to make sure the thread doesn't actually start the work loop
      # until it has a state and directive already set up, so use a queue to
      # temporarily block it.
      q = Queue.new

      @thread = Thread.new do
        q.pop

        loop do
          job = Job.work

          # Grab the lock and figure out what we should do next.
          synchronize do
            if @thread[:directive] == :stop
              @thread[:state] = :stopping
            elsif not job
              # No work, go to sleep.
              @thread[:state] = :sleeping
            end
          end

          if @thread[:state] == :sleeping
            sleep

            # Now that we're woken up, grab the lock figure out if we're stopping.
            synchronize do
              @thread[:state] = :stopping if @thread[:directive] == :stop
            end
          end

          break if @thread[:state] == :stopping
        end
      end

      synchronize do
        @thread[:directive] = :work
        @thread[:state]     = :working
      end

      q.push :go!
    end

    def sleeping?
      synchronize do
        if @thread[:state] == :sleeping
          # There's a very small period of time between when the Worker marks
          # itself as sleeping and when it actually goes to sleep. Only report
          # true when we're certain the thread is sleeping.
          sleep 0.0001 until @thread.status == 'sleep'
          true
        end
      end
    end

    def working?
      synchronize do
        @thread[:state] == :working
      end
    end

    def wake!
      synchronize do
        if sleeping?
          # Have to set the state here so that another thread checking
          # immediately after this won't see the worker as asleep.
          @thread[:state] = :working
          @thread.wakeup
          true
        end
      end
    end

    # This has to be called when trapping a SIGTERM, so it can't lock the monitor.
    def stop!
      @thread[:directive] = :stop
      @thread.wakeup
    end

    def wait_until_stopped
      @thread.join
    end

    private

    # Defaults for the Worker pool.
    @worker_count = 0
    @sleep_period = 5

    class << self
      attr_reader :mode, :sleep_period, :worker_count

      def mode=(mode)
        case mode
        when :async
          wrangler # Make sure the wrangler thread is initialized.
          self.worker_count = 4
        else
          self.worker_count = 0
        end

        @mode = mode
        Que.log :info, "Set mode to #{mode.inspect}"
      end

      def workers
        @workers ||= []
      end

      def worker_count=(count)
        if count > workers.count
          (count - workers.count).times { workers << new }
        elsif count < workers.count
          workers.pop(workers.count - count).each(&:stop!).each(&:wait_until_stopped)
        end
      end

      def sleep_period=(period)
        @sleep_period = period
        wrangler.wakeup if period
      end

      def wake!
        workers.find &:wake!
      end

      def wake_all!
        workers.each &:wake!
      end

      private

      def wrangler
        @wrangler ||= Thread.new { loop { sleep(*sleep_period); wake! } }
      end
    end
  end
end
