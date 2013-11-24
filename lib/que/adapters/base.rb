module Que
  module Adapters
    autoload :ActiveRecord,   'que/adapters/active_record'
    autoload :ConnectionPool, 'que/adapters/connection_pool'
    autoload :Single,         'que/adapters/single'
    autoload :Sequel,         'que/adapters/sequel'

    class Base
      def initialize(thing = nil)
        @wrappers = {}
      end

      # The only method that adapters really need to implement. Should lock a
      # connection so that no other threads are using it and yield it to the
      # block.
      def yield_connection(&block)
        raise NotImplementedError
      end

      def checkout(&block)
        yield_connection do |conn|
          yield @wrappers[conn] ||= new_wrapper(conn)
        end
      end

      def execute(command, *args)
        checkout do |conn|
          case command
            when Symbol then conn.execute_prepared(command, *args)
            when String then conn.execute(command, *args)
          end
        end
      end

      private

      def new_wrapper(conn)
        klass = case conn.class.to_s
                  when "PG::Connection", "Sequel::Postgres::Adapter" then Wrappers::PG
                  when /Java/                                        then Wrappers::JDBC
                  else raise "Unrecognized connection type: #{conn.inspect}"
                end

        klass.new(conn)
      end
    end
  end
end
