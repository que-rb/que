module Que
  class Sequel < Adapter
    def initialize(db)
      @db = db
    end

    def execute(sql)
      @db[sql].all
    end
  end
end
