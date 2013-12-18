require 'monitor'

module Que
  class Worker
    # Each worker has a thread that does the actual work of running jobs.
    # Since both the worker's thread and whatever thread is managing the
    # worker are capable of affecting the worker's state, we need to
    # synchronize access to it.
    include MonitorMixin

    # A custom exception to immediately kill a worker and its current job.
    class Stop < Interrupt; end

    attr_reader :thread, :state

    def initialize
      super # For MonitorMixin.
      @state  = :working
      @thread = Thread.new { work_loop }
    end

    def alive?
      !!@thread.status
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

    # #stop informs the worker that it should shut down after its next job,
    # while #stop! kills the job and worker immediately. #stop! is bad news
    # because its results are unpredictable (it can leave the DB connection
    # in an unusable state), so it should only be used when we're shutting
    # down the whole process anyway and side effects aren't a big deal.
    def stop
      synchronize do
        @stop = true
        @thread.wakeup if sleeping?
      end
    end

    def stop!
      @thread.raise Stop
    end

    def wait_until_stopped
      wait while alive?
    end

    private

    # Sleep very briefly while waiting for a thread to get somewhere.
    def wait
      sleep 0.0001
    end

    def work_loop
      loop do
        job = Job.work

        # Grab the lock and figure out what we should do next.
        synchronize { @state = :sleeping unless @stop || job }

        sleep if @state == :sleeping
        break if @stop
      end
    rescue Stop
      # This process is shutting down; let it.
    ensure
      @state = :stopped
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

      def stop!
        # Very rarely, #stop! won't have an effect on Rubinius.
        # Repeating it seems to work reliably, though.
        loop do
          break if workers.select(&:alive?).each(&:stop!).none?
          sleep 0.001
        end
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
