module Que
  class PG < Adapter
    def initialize(pg)
      @pg    = pg
      @mutex = Mutex.new
    end

    def checkout
      @mutex.synchronize { yield @pg }
    end
  end
end
