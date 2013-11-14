module Que
  class PG < Adapter
    def initialize(pg)
      @pg    = pg
      @mutex = Mutex.new
      execute "SET client_min_messages TO 'warning'" # Avoid annoying NOTICE messages.
    end

    def checkout
      @mutex.synchronize { yield @pg }
    end
  end
end
