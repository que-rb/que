module Que
  module Adapters
    class Sequel < Base
      def initialize(db)
        @db = db
        super
      end

      def checkout(&block)
        @db.synchronize(&block)
      end
    end
  end
end
