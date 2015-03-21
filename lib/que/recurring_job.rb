class Que::RecurringJob < Que::Job
  def initialize(attrs)
    @t_i, @t_f = attrs[:args].pop[:recurring_interval]
    super
  end

  def _run
    run(*attrs[:args])
    reenqueue unless @reenqueued || @destroyed
  end

  def start_time
    Time.at(@t_i)
  end

  def end_time
    Time.at(@t_f)
  end

  def time_range
    start_time...end_time
  end

  def next_run_float
    @t_f + self.class.interval
  end

  def next_run_time
    Time.at(next_run_float)
  end

  private

  def reenqueue
    new_args = attrs[:args] << {recurring_interval: [@t_f, next_run_float]}
    Que.execute :reenqueue_job, attrs.values_at(:queue, :priority, :run_at, :job_id, :job_class) << next_run_time << new_args
    @reenqueued = true
  end

  class << self
    attr_reader :interval

    def enqueue(*args)
      super(*args_with_interval(*args))
    end

    def run(*args)
      super(*args_with_interval(*args))
    end

    private

    def args_with_interval(*args)
      t = Time.now.utc.to_f.round(6) # Keep same precision as Postgres
      args << {recurring_interval: [t - interval, t]}
    end
  end
end
