require 'monitor'

module Que
  class Worker
    # Each worker has a thread that does the actual work of running jobs.
    # Since both the worker's thread and whatever thread is managing the
    # worker are capable of affecting the worker's state, we need to
    # synchronize access to it.
    include MonitorMixin

    attr_reader :thread, :state, :queue

    def initialize(queue = '')
      super() # For MonitorMixin.
      @queue  = queue
      @state  = :working
      @thread = Thread.new { work_loop }
      @thread.abort_on_exception = true
    end

    def alive?
      !!@thread.status
    end

    def sleeping?
      synchronize { _sleeping? }
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

    # This needs to be called when trapping a signal, so it can't lock the monitor.
    def stop
      @stop = true
      @thread.wakeup if _sleeping?
    end

    def wait_until_stopped
      wait while alive?
    end

    private

    # The interval in seconds between when the Que worker should perform a
    # "hard lock" by throwing out the last job ID it worked and locking without
    # using a predicate on `job_id`. The disadvantage of this is that the lock
    # may take significantly longer if a long running transaction has caused a
    # large number of dead tuples to accumulate in the table. The advantage is
    # that it allows any jobs with IDs lower than any current worker is
    # handling to be discovered and locked (that may happen in the case of a
    # crashed worker or an out-of-order transaction commit).
    HARD_LOCK_INTERVAL = 10

    # Sleep very briefly while waiting for a thread to get somewhere.
    def wait
      sleep 0.0001
    end

    def _sleeping?
      if @state == :sleeping
        # There's a very small period of time between when the Worker marks
        # itself as sleeping and when it actually goes to sleep. Only report
        # true when we're certain the thread is sleeping.
        wait until @thread.status == 'sleep'
        true
      end
    end

    def work_loop
      last_hard_lock_at = Time.now
      min_job_id = 0

      loop do
        cycle = nil

        if Que.mode == :async
          time   = Time.now
          result = Job.work(queue, min_job_id)

          case result[:event]
          when :job_unavailable
            cycle = false
            result[:level] = :debug
          when :job_race_condition
            cycle = true
            result[:level] = :debug
          when :job_worked
            cycle = true
            min_job_id = result[:job][:job_id]
            result[:elapsed] = (Time.now - time).round(5)
          when :job_errored
            # For PG::Errors, assume we had a problem reaching the database, and
            # don't hit it again right away.
            cycle = !result[:error].is_a?(PG::Error)
            result[:error] = {:class => result[:error].class.to_s, :message => result[:error].message}
          else
            raise "Unknown Event: #{result[:event].inspect}"
          end

          # Every so often try to take a lock the "hard" way, which is to say,
          # without a predicate on `job_id`. This may help to discover jobs
          # that have been bypassed due to a crashed worker or out-of-order
          # transaction commit.
          if HARD_LOCK_INTERVAL == 0 || Time.now > last_hard_lock_at + HARD_LOCK_INTERVAL
            last_hard_lock_at = Time.now
            min_job_id = 0
          end

          Que.log(result)
        end

        synchronize { @state = :sleeping unless cycle || @stop }
        sleep if @state == :sleeping
        break if @stop
      end
    ensure
      @state = :stopped
    end

    # Setting Que.wake_interval = nil should ensure that the wrangler thread
    # doesn't wake up a worker again, even if it's currently sleeping for a
    # set period. So, we double-check that @wake_interval is set before waking
    # a worker, and make sure to wake up the wrangler when @wake_interval is
    # changed in Que.wake_interval= below.
    @wake_interval = 5

    # Four workers is a sensible default for most use cases.
    @worker_count = 4

    class << self
      attr_reader :mode, :wake_interval, :worker_count
      attr_accessor :queue_name

      # In order to work in a forking webserver, we need to be able to accept
      # worker_count and wake_interval settings without actually instantiating
      # the relevant threads until the mode is actually set to :async in a
      # post-fork hook (since forking will kill any running background threads).

      def mode=(mode)
        Que.log :event => 'mode_change', :value => mode.to_s
        @mode = mode

        if mode == :async
          set_up_workers
          wrangler
        end
      end

      def worker_count=(count)
        Que.log :event => 'worker_count_change', :value => count.to_s
        @worker_count = count
        set_up_workers if mode == :async
      end

      def workers
        @workers ||= []
      end

      def wake_interval=(interval)
        @wake_interval = interval
        wrangler.wakeup if mode == :async
      end

      def wake!
        workers.find(&:wake!)
      end

      def wake_all!
        workers.each(&:wake!)
      end

      private

      def set_up_workers
        if worker_count > workers.count
          workers.push(*(worker_count - workers.count).times.map{new(queue_name || '')})
        elsif worker_count < workers.count
          workers.pop(workers.count - worker_count).each(&:stop).each(&:wait_until_stopped)
        end
      end

      def wrangler
        @wrangler ||= Thread.new do
          loop do
            sleep(*@wake_interval)
            wake! if @wake_interval && mode == :async
          end
        end
      end
    end
  end
end
