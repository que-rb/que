# frozen_string_literal: true

# A wrapper around whatever connection pool we're using. Mainly just asserts
# that the source connection pool is reentrant and thread-safe.

module Que
  class ConnectionPool
    def initialize(&block)
      @connection_proc = block
      @checked_out     = Set.new
      @mutex           = Mutex.new
      @thread_key      = "que_connection_pool_#{object_id}".to_sym
    end

    def checkout
      # Do some asserting to ensure that the connection pool we're using is
      # behaving properly.
      @connection_proc.call do |conn|
        # Did this pool already have a connection for this thread?
        preexisting = wrapped = current_connection

        begin
          if preexisting
            # If so, check that the connection we just got is the one we expect.
            if preexisting.wrapped_connection.backend_pid != conn.backend_pid
              raise Error, "Connection pool is not reentrant! previous: #{preexisting.wrapped_connection.inspect} now: #{conn.inspect}"
            end
          else
            # If not, make sure that it wasn't promised to any other threads.
            sync do
              Que.assert(@checked_out.add?(conn.backend_pid)) do
                "Connection pool didn't synchronize access properly! (entrance: #{conn.backend_pid})"
              end
            end

            self.current_connection = wrapped = Connection.wrap(conn)
          end

          yield(wrapped)
        ensure
          if preexisting.nil?
            # We're at the top level (about to return this connection to the
            # pool we got it from), so mark it as no longer ours.
            self.current_connection = nil

            sync do
              Que.assert(@checked_out.delete?(conn.backend_pid)) do
                "Connection pool didn't synchronize access properly! (exit: #{conn.backend_pid})"
              end
            end
          end
        end
      end
    end

    def execute(*args)
      checkout { |conn| conn.execute(*args) }
    end

    def in_transaction?
      checkout { |conn| conn.in_transaction? }
    end

    private

    def sync(&block)
      @mutex.synchronize(&block)
    end

    def current_connection
      Thread.current[@thread_key]
    end

    def current_connection=(c)
      Thread.current[@thread_key] = c
    end
  end
end
