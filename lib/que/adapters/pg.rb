require 'monitor'

module Que
  module Adapters
    class PG < Base
      def initialize(pg)
        @pg      = pg
        @monitor = Monitor.new
      end

      def checkout
        @monitor.synchronize { yield @pg }
      end
    end
  end
end
