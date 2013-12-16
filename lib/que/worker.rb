require 'monitor'

module Que
  class Worker
    # Each worker has a thread that does the actual work of running jobs.
    # Since both the worker's thread and whatever thread is managing the
    # worker are capable of affecting the state of the worker's thread, we
    # need to synchronize access to it.

    include MonitorMixin

    attr_reader :thread, :state

    def initialize
      super # For MonitorMixin.

      @state = :working

      @thread = Thread.new do
        loop do
          job = Job.work

          # Grab the lock and figure out what we should do next.
          synchronize do
            if @stopping
              @state = :stopping
            elsif not job
              # No work, go to sleep.
              @state = :sleeping
            end
          end

          if @state == :sleeping
            sleep

            # Now that we're woken up, grab the lock and figure out whether we're stopping.
            synchronize { @state = :stopping if @stopping }
          end

          break if @state == :stopping
        end
      end
    end

    def sleeping?
      synchronize do
        if @state == :sleeping
          # There's a very small period of time between when the Worker marks
          # itself as sleeping and when it actually goes to sleep. Only report
          # true when we're certain the thread is sleeping.
          wait until @thread.status == 'sleep'
          true
        end
      end
    end

    def working?
      synchronize { @state == :working }
    end

    def wake!
      synchronize do
        if sleeping?
          # Have to set the state here so that another thread checking
          # immediately after this won't see the worker as asleep.
          @state = :working
          @thread.wakeup
          true
        end
      end
    end

    # stop and wait_until_stopped have to be called when trapping a SIGTERM, so they can't lock the monitor.
    def stop
      @stopping = true
    end

    def wait_until_stopped
      loop do
        case @thread.status
          when false   then break
          when 'sleep' then @thread.wakeup
        end

        wait
      end
    end

    private

    # Sleep very briefly while waiting for a thread to get somewhere.
    def wait
      sleep 0.0001
    end

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
          workers.pop(workers.count - count).each(&:stop).each(&:wait_until_stopped)
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
