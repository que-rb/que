# Wrapper to manage interactions with PG::Connection objects, wherever they come from.

module Que
  module Wrappers
    class PG < Base
      def execute(*args)
        @connection.async_exec(*args)
      end

      def execute_prepared(name, params = [])
        unless @statements[name]
          @connection.prepare("que_#{name}", SQL[name])
          @statements[name] = true
        end

        @connection.exec_prepared("que_#{name}", params)
      end
    end
  end
end
