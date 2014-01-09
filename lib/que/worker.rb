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
        @thread[:que_stopping] = true
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
        synchronize { @state = :sleeping unless @thread[:que_stopping] || job }
        sleep if @state == :sleeping
        break if @thread[:que_stopping]
      end
    rescue Stop
      # This process is shutting down - let it.
    ensure
      @state = :stopped
    end

    # Setting Que.wake_interval = nil should ensure that the wrangler thread
    # doesn't wake up a worker again, even if it's currently sleeping for a
    # set period. So, we double-check that @wake_interval is set before waking
    # a worker, and make sure to wake up the wrangler when @wake_interval is
    # changed in Que.wake_interval= below.
    @wake_interval = 5
    @wrangler = Thread.new do
      loop do
        sleep *@wake_interval
        wake! if @wake_interval
      end
    end

    class << self
      attr_reader :mode, :wake_interval

      def mode=(mode)
        case set_mode(mode)
        when :async
          set_worker_count 4 if worker_count.zero?
        when :sync, :off
          set_worker_count 0
        end
      end

      def workers
        @workers ||= []
      end

      def worker_count=(count)
        set_mode(count > 0 ? :async : :off)
        set_worker_count(count)
      end

      def worker_count
        workers.count
      end

      def wake_interval=(interval)
        @wake_interval = interval
        @wrangler.wakeup
      end

      def stop!
        # The behavior of Worker#stop! is unpredictable - what it does is
        # dependent on what the Worker is currently doing. Sometimes it won't
        # work the first time, so we need to try again, but sometimes it'll
        # never do anything, so we can't repeat indefinitely. So, compromise.
        5.times do
          break if workers.select(&:alive?).each(&:stop!).none?
          sleep 0.001
        end

        workers.clear
      end

      def wake!
        workers.find &:wake!
      end

      def wake_all!
        workers.each &:wake!
      end

      private

      def set_mode(mode)
        if mode != @mode
          Que.log :info, "Set mode to #{mode.inspect}"
          @mode = mode
        end
      end

      def set_worker_count(count)
        if count != worker_count
          Que.log :info, "Set worker_count to #{count.inspect}"

          if count > worker_count
            workers.push *(count - worker_count).times.map{new}
          elsif count < worker_count
            workers.pop(worker_count - count).each(&:stop).each(&:wait_until_stopped)
          end
        end
      end
    end
  end
end
