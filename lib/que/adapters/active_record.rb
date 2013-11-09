module Que
  class ActiveRecord < Adapter
    def initialize
    end

    def execute(sql)
      connection.execute(sql).to_a
    end

    private

    def connection
      ::ActiveRecord::Base.connection
    end
  end
end
