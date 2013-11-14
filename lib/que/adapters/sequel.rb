module Que
  class Sequel < Adapter
    def initialize(db)
      @db = db
    end

    def execute(*args)
      @db.synchronize { |conn| conn.async_exec(*args) }
    end
  end
end
