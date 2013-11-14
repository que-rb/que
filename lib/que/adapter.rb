module Que
  class Adapter
    def initialize(thing = nil)
      raise NotImplementedError
    end

    def checkout(&block)
      raise NotImplementedError
    end

    def execute(*args)
      checkout { |conn| conn.async_exec(*args) }
    end
  end
end
