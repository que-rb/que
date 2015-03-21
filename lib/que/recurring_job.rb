class Que::RecurringJob < Que::Job
  def _run
    @t_i, @t_f = attrs[:args].pop[:recurring_interval]
    run(*attrs[:args])
    reenqueue unless @reenqueued || @destroyed
  end

  private

  def reenqueue
    next_run_utc = @t_f + self.class.interval
    next_run_time = Time.at(next_run_utc).utc
    args = attrs[:args] << {recurring_interval: [@t_f, next_run_utc]}

    params = attrs.values_at(:queue, :priority, :run_at, :job_id)
    params << attrs[:queue] << attrs[:priority] << next_run_time << attrs[:job_class] << args

    Que.execute :reenqueue_job, params
    @reenqueued = true
  end

  class << self
    attr_reader :interval

    def enqueue(*args)
      t = Time.now.utc.to_f.round(6) # Keep same precision as Postgres
      args << {recurring_interval: [t - interval, t]}
      super(*args)
    end
  end
end
