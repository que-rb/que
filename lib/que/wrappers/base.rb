module Que
  module Wrappers
    autoload :PG,   'que/wrappers/pg'
    autoload :JDBC, 'que/wrappers/jdbc'

    class Base
      def initialize(conn)
        @connection = conn
        @statements = {}
      end

      def execute(*args)
        raise NotImplementedError
      end

      def execute_prepared(*args)
        raise NotImplementedError
      end
    end
  end
end
