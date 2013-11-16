module Que
  module Adapters
    class ActiveRecord < Base
      def checkout
        ::ActiveRecord::Base.connection_pool.with_connection { |conn| yield conn.raw_connection }
      end
    end
  end
end
