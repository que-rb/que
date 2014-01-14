require 'monitor'

module Que
  class Worker
    # Each worker has a thread that does the actual work of running jobs.
    # Since both the worker's thread and whatever thread is managing the
    # worker are capable of affecting the worker's state, we need to
    # synchronize access to it.
    include MonitorMixin

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

    def stop
      synchronize do
        @stop = true
        @thread.wakeup if sleeping?
      end
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
        time  = Time.now
        cycle = nil

        event, object = Job.work
        data = {:event => event}

        case event
        when :job_unavailable
          cycle = false
        when :job_race_condition
          cycle = true
        when :job_worked
          cycle = true
          data.merge! :elapsed => (Time.now - time).round(5), :job => object.attrs
        when :job_errored
          # For PG::Errors, assume we had a problem reaching the database, and
          # don't hit it again right away.
          cycle = !object.is_a?(PG::Error)
          data.merge! :error_class => object.class.to_s, :error_message => object.message
        else
          raise "Unknown Event: #{event.inspect}"
        end

        Que.log(data)

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

      def wake!
        workers.find &:wake!
      end

      def wake_all!
        workers.each &:wake!
      end

      private

      def set_mode(mode)
        if mode != @mode
          Que.log :event => 'mode_change', :value => mode.to_s
          @mode = mode
        end
      end

      def set_worker_count(count)
        if count != worker_count
          Que.log :event => 'worker_count_change', :value => count.to_s

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
