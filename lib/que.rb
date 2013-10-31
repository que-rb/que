require 'que/version'

module Que
  autoload :Job,    'que/job'
  autoload :Worker, 'que/worker'

  class << self
    attr_accessor :logger
  end
end
