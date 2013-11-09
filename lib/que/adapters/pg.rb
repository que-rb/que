module Que
  class PG < Adapter
    def initialize(pg)
      @pg = pg
    end

    def execute(sql)
      @pg.async_exec(sql).to_a
    end
  end
end
