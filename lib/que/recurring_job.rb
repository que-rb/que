# Inherit from RecurringJob instead of Job for simple but reliable recurring
# jobs.

module Que
  class RecurringJob < Job
    def initialize(attrs)
      @_start_time, @_end_time = attrs[:args].shift[:recurring_interval]
      # Hang onto a deep copy of the args so that if the job mutates them, that won't be passed on to the next job.
      @_args_copy = JSON_MODULE.load(JSON_MODULE.dump(attrs[:args]))
      super
    end

    def _run
      run(*attrs[:args])
      reenqueue unless @reenqueued || @destroyed
    end

    def start_time
      Time.at(@_start_time)
    end

    def end_time
      Time.at(@_end_time)
    end

    def time_range
      start_time...end_time
    end

    def next_run_float
      @_end_time + self.class.interval
    end

    def next_run_time
      Time.at(next_run_float)
    end

    private

    def reenqueue(interval: nil, args: nil)
      args     ||= @_args_copy
      interval ||= self.class.interval

      new_args = args.unshift(recurring_interval: [@_end_time, @_end_time + interval])
      next_run_time = Time.at(end_time + interval)

      Que.execute :reenqueue_job, attrs.values_at(:priority, :run_at, :job_id, :job_class) << next_run_time << new_args
      @reenqueued = true
    end

    class << self
      def interval
        @interval || raise(Error, "Can't enqueue a recurring job (#{to_s}) unless an interval is set!")
      end

      def enqueue(*args)
        super(*args_with_interval(*args))
      end

      def run(*args)
        super(*args_with_interval(*args))
      end

      private

      def args_with_interval(*args)
        time  = (args.last.is_a?(Hash) && args.last[:run_at]) || Time.now
        float = time.utc.to_f.round(6) # Keep same precision as Postgres
        args.unshift(recurring_interval: [float - interval, float])
      end
    end
  end
end
