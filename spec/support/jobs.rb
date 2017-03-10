# frozen_string_literal: true

# Common Job classes for use in specs.

# Handy for blocking in the middle of processing a job.
class BlockJob < Que::Job
  def run
    $q1.push nil
    $q2.pop
  end
end



class ErrorJob < Que::Job
  def run
    raise "ErrorJob!"
  end
end



class ArgsJob < Que::Job
  def run(*args)
    $passed_args = args
  end
end
