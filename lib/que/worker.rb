require 'monitor'

module Que
  class Worker
    # Each worker has a thread that does the actual work of running jobs.
    # Since both the worker's thread and whatever thread is managing the
    # worker are capable of affecting the state of the worker's thread, we
    # need to synchronize access to it.

    # We use two variables to track the current state of the worker,
    # @thread[:state] and @thread[:directive].
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

    def asleep?
      synchronize do
        if @thread[:state] == :sleeping
          # There's a very small period of time between when the Worker marks
          # itself as sleeping and when it actually goes to sleep. Only report
          # #asleep? as true when we're certain the thread is sleeping.
          wait until @thread.status == 'sleep'
          true
        end
      end
    end

    def wake!
      synchronize do
        if asleep?
          # Set the state here so that another thread checking immediately
          # after this won't see the worker as asleep.
          @thread[:state] = :working
          @thread.wakeup
          true
        end
      end
    end

    def stop!
      synchronize do
        @thread[:directive] = :stop
        wake! if asleep?
      end
    end

    def wait_until_stopped
      @thread.join
    end

    private

    WaitPeriod = 0.0001 # 0.1 ms

    def wait
      sleep WaitPeriod
    end
  end
end
