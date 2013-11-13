module Que
  class Adapter
    def initialize(thing = nil)
      raise NotImplementedError
    end

    def execute(*args)
      raise NotImplementedError
    end
  end
end
