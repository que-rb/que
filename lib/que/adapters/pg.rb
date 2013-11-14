require 'monitor'

module Que
  class PG < Adapter
    def initialize(pg)
      @pg      = pg
      @monitor = Monitor.new
    end

    def checkout
      @monitor.synchronize { yield @pg }
    end
  end
end
