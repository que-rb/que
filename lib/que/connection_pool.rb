# frozen_string_literal: true

# A wrapper around whatever connection pool we're using.

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
            unless preexisting.wrapped_connection.object_id == conn.object_id
              raise Error, "Connection pool is not reentrant!"
            end
          else
            # If not, make sure that it wasn't promised to any other threads.
            sync do
              Que.assert(@checked_out.add?(conn.object_id)) do
                "Connection pool didn't synchronize access properly! (entrance)"
              end
            end

            self.current_connection = wrapped = Connection.new(conn)
          end

          yield(wrapped)
        ensure
          unless preexisting
            # If we're at the top level (about to return this connection to the
            # pool we got it from), mark it as no longer ours.
            self.current_connection = nil

            sync do
              Que.assert(@checked_out.delete?(conn.object_id)) do
                "Connection pool didn't synchronize access properly! (exit)"
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

    def sync
      @mutex.synchronize { yield }
    end

    def current_connection
      Thread.current[@thread_key]
    end

    def current_connection=(c)
      Thread.current[@thread_key] = c
    end
  end
end
