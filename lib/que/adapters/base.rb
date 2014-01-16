module Que
  module Adapters
    autoload :ActiveRecord,   'que/adapters/active_record'
    autoload :ConnectionPool, 'que/adapters/connection_pool'
    autoload :PG,             'que/adapters/pg'
    autoload :Sequel,         'que/adapters/sequel'

    class Base
      def initialize(thing = nil)
        @prepared_statements = {}
      end

      # The only method that adapters really need to implement. Should lock a
      # PG::Connection (or something that acts like a PG::Connection) so that
      # no other threads are using it and yield it to the block. Should also
      # be re-entrant.
      def checkout(&block)
        raise NotImplementedError
      end

      def execute(*args)
        checkout { |conn| conn.async_exec(*args) }
      end

      def execute_prepared(name, params = [])
        checkout do |conn|
          statements = @prepared_statements[conn] ||= {}

          unless statements[name]
            conn.prepare("que_#{name}", SQL[name])
            statements[name] = true
          end

          conn.exec_prepared("que_#{name}", params)
        end
      end

      def in_transaction?
        checkout { |conn| conn.transaction_status != ::PG::PQTRANS_IDLE }
      end
    end
  end
end
