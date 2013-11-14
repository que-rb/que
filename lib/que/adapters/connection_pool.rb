module Que
  class ConnectionPool < Adapter
    def initialize(pool)
      @pool = pool
    end

    def checkout(&block)
      @pool.with(&block)
    end
  end
end
