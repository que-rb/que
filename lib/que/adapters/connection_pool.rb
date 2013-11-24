module Que
  module Adapters
    class ConnectionPool < Base
      def initialize(pool)
        @pool = pool
        super
      end

      def yield_connection(&block)
        @pool.with(&block)
      end
    end
  end
end
