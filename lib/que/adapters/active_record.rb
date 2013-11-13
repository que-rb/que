module Que
  class ActiveRecord < Adapter
    def initialize
    end

    def execute(*args)
      connection.async_exec(*args).to_a
    end

    private

    def connection
      ::ActiveRecord::Base.connection.raw_connection
    end
  end
end
