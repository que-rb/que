module Que
  class Adapter
    def initialize(thing = nil)
      raise NotImplementedError
    end

    def execute(sql)
      raise NotImplementedError
    end
  end
end
