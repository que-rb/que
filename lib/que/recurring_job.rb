class Que::RecurringJob < Que::Job
  private

  def reenqueue
    params = attrs.values_at(:queue, :priority, :run_at, :job_id)
    params << attrs[:queue]
    params << attrs[:priority]
    params << attrs[:run_at] + self.class.interval
    params << attrs[:job_class]
    params << attrs[:args]

    Que.execute :reenqueue_job, params
  end

  class << self
    attr_reader :interval
  end
end
