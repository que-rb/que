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



    ### Error Handling ###

    # error_handler is just a proc that is passed errors raised by jobs when
    # they occur.
    attr_accessor :error_handler



    ### Logging ###

    attr_writer :logger, :log_formatter

    def logger
      @logger.respond_to?(:call) ? @logger.call : @logger
    end

    def log_formatter
      @log_formatter ||= JSON_MODULE.method(:dump)
    end



    ### JSON Conversion ###

    attr_writer :json_converter

    def json_converter
      @json_converter ||= SYMBOLIZER
    end



    ### Mode/Locker ###

    # To be removed...?
    attr_reader :mode
    attr_reader :locker

    def mode=(mode)
      if @mode != mode
        case mode
        when :async
          @locker = Locker.new
        when :sync, :off
          if @locker
            @locker.stop
            @locker = nil
          end
        else
          raise Error, "Unknown Que mode: #{mode.inspect}"
        end

        log level: :debug, event: :mode_change, value: mode
        @mode = mode
      end
    end



    ### Constantizing ###

    # This is something that has needed configuration in Rails in the past, so
    # here we go.

    attr_writer :constantizer

    def constantizer
      @constantizer ||= proc { |string| string.split('::').inject(Object, &:const_get) }
    end
  end
end
