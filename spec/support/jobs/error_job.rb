# frozen_string_literal: true

class ErrorJob < Que::Job
  def run
    raise "ErrorJob!"
  end
end
