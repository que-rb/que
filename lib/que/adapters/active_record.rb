module Que
  module Adapters
    class ActiveRecord < Base
      def yield_connection
        ::ActiveRecord::Base.connection_pool.with_connection do |conn|
          # TODO: Make this not terrible.
          c = conn.raw_connection
          case c.class.to_s
            when "PG::Connection" then yield c
            when /Jdbc/           then yield c.connection
            else raise "Unrecognized connection! #{c.inspect}"
          end
        end
      end
    end
  end
end
