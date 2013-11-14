module Que
  class Sequel < Adapter
    def initialize(db)
      @db = db
    end

    def checkout(&block)
      @db.synchronize(&block)
    end
  end
end
