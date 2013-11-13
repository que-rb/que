module Que
  class PG < Adapter
    def initialize(pg)
      @pg = pg
      execute "SET client_min_messages TO 'warning'" # Avoid annoying NOTICE messages.
    end

    def execute(sql)
      @pg.async_exec(sql).to_a
    end
  end
end
