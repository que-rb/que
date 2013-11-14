module Que
  class ConnectionPool < Adapter
    def initialize(pool)
      @pool = pool
    end

    def execute(*args)
      @pool.with { |conn| conn.async_exec(*args) }
    end
  end
end
