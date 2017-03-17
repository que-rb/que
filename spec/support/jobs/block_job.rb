# frozen_string_literal: true

# Handy for blocking in the middle of processing a job.
class BlockJob < Que::Job
  def run
    $q1.push nil
    $q2.pop
  end
end
