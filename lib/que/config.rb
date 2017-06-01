# frozen_string_literal: true

# Que's global configuration lives here.

module Que
  DEFAULT_JSON_DESERIALIZER = -> (json) do
    JSON.parse(json, symbolize_names: true, create_additions: false)
  end

  class << self
    ### Connection Setup ###

    # The primary way of integrating Que with a connection pool - pass it a
    # reentrant block that locks and yields a Postgres connection.
    def connection_proc=(connection_proc)
      @pool = connection_proc && ConnectionPool.new(&connection_proc)
    end

    # How to actually access Que's established connection pool.
    def pool
      @pool || raise(Error, "Que connection not established!")
    end

    # Set the current pool. Helpful for specs, but probably shouldn't be used
    # generally.
    attr_writer :pool



    ### Error Handling ###

    # error_notifier is just a proc that is passed errors raised by jobs when
    # they occur.
    attr_accessor :error_notifier



    ### Logging ###

    attr_writer :logger, :log_formatter

    def logger
      @logger.respond_to?(:call) ? @logger.call : @logger
    end

    def log_formatter
      @log_formatter ||= JSON.method(:dump)
    end



    ### JSON Conversion ###

    attr_writer :json_serializer, :json_deserializer

    def json_deserializer
      @json_deserializer ||= DEFAULT_JSON_DESERIALIZER
    end

    def json_serializer
      @json_serializer ||= JSON.method(:dump)
    end



    ### Default ###

    attr_writer :default_queue

    def default_queue
      @default_queue || DEFAULT_QUEUE
    end



    ### Constantizing ###

    # This is something that has needed configuration in Rails in the past, so
    # here we go.

    attr_writer :constantizer

    def constantizer
      @constantizer ||=
        -> (string) { string.split('::').inject(Object, &:const_get) }
    end
  end
end
