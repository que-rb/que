# frozen_string_literal: true

class ArgsJob < Que::Job
  def run(*args)
    $passed_args = args
  end
end
