module Que
  class ActiveRecord < Adapter
    def initialize
    end

    def execute(*args)
      ::ActiveRecord::Base.connection.raw_connection.async_exec(*args)
    end
  end
end
