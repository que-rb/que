# frozen_string_literal: true

# Que's global configuration lives here.

module Que
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



    ### Default ###

    attr_writer :default_queue

    def default_queue
      @default_queue || DEFAULT_QUEUE
    end
  end
end
