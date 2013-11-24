require 'monitor'

# Very simple adapter for when Que is given a single connection to use.
module Que
  module Adapters
    class Single < Base
      def initialize(conn)
        @conn = conn
        @lock = Monitor.new # Must be re-entrant.
        super
      end

      def yield_connection
        @lock.synchronize { yield @conn }
      end
    end
  end
end
