module Que
  # There are multiple workers running at a given time, each with a given
  # minimum priority that they care about for jobs. A worker will continuously
  # look for jobs and work them. If there's no job available, the worker will go
  # to sleep until it is awakened by an external thread.

  # Use Worker.state = ... to set the current state. There are three states:
  #   :async => Work jobs in dedicated threads. Used in production.
  #   :sync  => Work jobs immediately, as they're queued, in the current thread. Used in testing.
  #   :off   => Don't work jobs at all. Must use Job#work or Job.work explicitly.

  # Worker.wake! will wake up the sleeping worker with the lowest minimum job
  # priority. Worker.wake! may be run by another thread handling a web request,
  # or by the wrangler thread (which wakes a worker every five seconds, to
  # handle scheduled jobs). It only has an effect when running in async mode.

  class Worker
    # Each worker has a corresponding thread, which contains two variables:
    # :directive, to define what it should be doing, and :state, to define what
    # it's actually doing at the moment. Need to be careful that these variables
    # are only modified by a single thread at a time (hence, MonitorMixin).
    include MonitorMixin

    # The Worker class itself needs to be protected as well, to make sure that
    # multiple threads aren't stopping/starting it at the same time.
    extend MonitorMixin

    # Default worker priorities. Rule of thumb: number of lowest-priority
    # workers should equal number of processors available to us.
    PRIORITIES = [5, 5, 5, 5, 4, 3, 2, 1].freeze

    # Which errors should signal a worker that it should hold off before trying
    # to grab another job, in order to avoid spamming the logs.
    DELAYABLE_ERRORS = %w(
      Sequel::DatabaseConnectionError
      Sequel::DatabaseDisconnectError
    )

    # How long the wrangler thread should wait between pings of the database.
    # Future directions: when we have multiple dynos, add rand() to this value
    # in the wrangler loop below, so that the dynos' checks will be spaced out.
    SLEEP_PERIOD = 5

    # How long to sleep, in repeated increments, for something to happen.
    WAIT_PERIOD = 0.0001 # 0.1 ms

    # How long a worker should wait before trying to get another job, in the
    # event of a database connection problem.
    ERROR_PERIOD = 5

    attr_reader :thread, :priority

    def initialize(priority)
      super() # For MonitorMixin

      # These threads have a bad habit of never even having their directive and
      # state set if we do it inside their threads. So instead, force the issue
      # by doing it outside and holding them up via a queue until their initial
      # state is set.
      q = Queue.new

      @priority = priority
      @thread = Thread.new do
        q.pop
        job = nil

        loop do
          sleep! unless work_job

          if @thread[:directive] == :sleep
            @thread[:state] = :sleeping
            sleep
          end
        end
      end

      # All workers are working when first instantiated.
      synchronize { @thread[:directive], @thread[:state] = :work, :working }

      # Now the worker can start.
      q.push nil

      # Default thread priority is 0 - make worker threads a bit less important
      # than threads that are handling requests.
      @thread.priority = -1
    end

    # If the worker is asleep, wakes it up and returns truthy. If it's already
    # awake, does nothing and returns falsy.
    def wake!
      synchronize do
        if sleeping?
          # There's a very brief period of time where the worker may be marked
          # as sleeping but the thread hasn't actually gone to sleep yet.
          wait until @thread.stop?
          @thread[:directive] = :work

          # Have to set state here so that another poke immediately after this
          # one doesn't see the current state as sleeping.
          @thread[:state] = :working

          # Now it's safe to wake up the worker.
          @thread.wakeup
        end
      end
    end

    def sleep!
      synchronize { @thread[:directive] = :sleep }
    end

    def awake?
      synchronize do
        @thread[:state].in?(%i(sleeping working)) &&
        @thread[:directive].in?(%i(sleep work)) &&
        @thread.status.in?(%w(sleep run))
      end
    end

    def wait_for_sleep
      wait until synchronize { sleeping? }
    end

    private

    def work_job
      Job.work(:priority => priority)
    rescue => error
      self.class.notify_error "Worker error!", error
      sleep ERROR_PERIOD if error.class.to_s.in? DELAYABLE_ERRORS
      return true # There's work available.
    end

    def sleeping?
      @thread[:state] == :sleeping
    end

    def wait
      sleep WAIT_PERIOD
    end

    # The Worker class is responsible for managing the worker instances.
    class << self
      def state=(state)
        synchronize do
          Que.logger.info "Setting Worker to #{state}..."
          case state
          when :async
            # If this is the first time starting up Worker, start up all workers
            # immediately, for the case of a restart during heavy app usage.
            workers
            # Make sure the wrangler thread is running, it'll do the rest.
            @wrangler ||= Thread.new { loop { wrangle } }
          when :sync, :off
            # Put all the workers to sleep.
            workers.each(&:sleep!).each(&:wait_for_sleep)
          else
            raise "Bad Worker state! #{state.inspect}"
          end

          Que.logger.info "Set Worker to #{state}"
          @state = state
        end
      end

      def state
        synchronize { @state ||= :off }
      end

      def async?
        state == :async
      end

      # All workers are up and processing jobs?
      def up?(*states)
        synchronize { async? && workers.map(&:priority) == PRIORITIES && workers.all?(&:awake?) }
      end

      def workers
        @workers || synchronize { @workers ||= PRIORITIES.map { |i| new(i) } }
      end

      # Wake up just one worker to work a job, if running async.
      def wake!
        synchronize { async? && workers.find(&:wake!) }
      end

      def notify_error(message, error)
        log_error message, error
        #ExceptionNotifier.notify_exception(error)
      rescue => error
        log_error "Error notification error!", error
      end

      private

      # The wrangler runs this method continuously.
      def wrangle
        sleep SLEEP_PERIOD
        wake!
      rescue => error
        notify_error "Wrangler Error!", error
      end

      def log_error(message, error)
        Que.logger.error <<-ERROR
          #{message}
          #{error.message}
          #{error.backtrace.join("\n")}
        ERROR
      end
    end
  end
end
