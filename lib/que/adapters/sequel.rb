module Que
  module Adapters
    class Sequel < Base
      def initialize(db)
        @db = db
        super
      end

      def yield_connection(&block)
        @db.synchronize(&block)
      end
    end
  end
end
