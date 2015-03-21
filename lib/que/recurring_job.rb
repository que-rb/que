class Que::RecurringJob < Que::Job
  private

  def reenqueue
    # TODO: Cover these two statements in a transaction? Or use a writable CTE?
    destroy
    self.class.enqueue(*@attrs[:args], run_at: @attrs[:run_at] + self.class.interval)
  end

  class << self
    attr_reader :interval
  end
end
