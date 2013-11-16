module Que
  module Adapters
    autoload :ActiveRecord,   'que/adapters/active_record'
    autoload :ConnectionPool, 'que/adapters/connection_pool'
    autoload :PG,             'que/adapters/pg'
    autoload :Sequel,         'que/adapters/sequel'

    class Base
      def initialize(thing = nil)
        raise NotImplementedError
      end

      def checkout(&block)
        raise NotImplementedError
      end

      def execute(*args)
        checkout { |conn| conn.async_exec(*args) }
      end

      def execute_prepared(name, params = [])
        checkout do |conn|
          unless statements_prepared(conn)[name]
            conn.prepare("que_#{name}", SQL[name])
            statements_prepared(conn)[name] = true
          end

          conn.exec_prepared("que_#{name}", params)
        end
      end

      private

      # Each adapter needs to remember which of its connections have prepared
      # which statements. This is a shared data structure, so protect it. We
      # assume that the hash of statements for a particular connection is only
      # being accessed by the thread that's checked it out, though.
      @@mutex = Mutex.new

      def statements_prepared(conn)
        @@mutex.synchronize do
          @statements_prepared       ||= {}
          @statements_prepared[conn] ||= {}
        end
      end
    end
  end
end
