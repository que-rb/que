# Que's global configuration lives here.

module Que
  class << self
    ### Connection Setup ###

    # The primary way of integrating Que with a connection pool - pass it a
    # reentrant block that locks and yields a Postgres connection.
    def connection_proc=(connection_proc)
      @pool = connection_proc && ConnectionPool.new(&connection_proc)
    end

    # connection= is here for backwards compatibility, and delegates to
    # connection_proc= depending on the input.
    def connection=(connection)
      self.connection_proc =
        if connection.to_s == 'ActiveRecord'
          proc { |&block| ActiveRecord::Base.connection_pool.with_connection { |conn| block.call(conn.raw_connection) } }
        else
          case connection.class.to_s
            when 'Sequel::Postgres::Database' then connection.method(:synchronize)
            when 'ConnectionPool'             then connection.method(:with)
            when 'Pond'                       then connection.method(:checkout)
            when 'PG::Connection'             then raise "Que now requires a connection pool and can no longer use a plain PG::Connection."
            when 'NilClass'                   then connection
            else raise Error, "Que connection not recognized: #{connection.inspect}"
          end
        end
    end

    # How to actually access Que's established connection pool.
    def pool
      @pool || raise(Error, "Que connection not established!")
    end

    # Set the current pool. Helpful for specs, but probably shouldn't be used generally.
    attr_writer :pool
  end
end
