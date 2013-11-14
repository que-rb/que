module Que
  class ActiveRecord < Adapter
    def initialize
    end

    def checkout
      ::ActiveRecord::Base.connection_pool.with_connection { |conn| yield conn.raw_connection }
    end
  end
end
