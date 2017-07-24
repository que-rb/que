# frozen_string_literal: true

# A wrapper around whatever connection pool we're using.

require 'time' # For Time.parse

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
        preexisting = current_connection

        begin
          if preexisting
            # If so, check that the connection we just got is the one we expect.
            unless preexisting.object_id == conn.object_id
              raise Error, "Connection pool is not reentrant!"
            end
          else
            # If not, make sure that it wasn't promised to any other threads.
            sync do
              Que.assert(@checked_out.add?(conn.object_id)) do
                "Connection pool didn't synchronize access properly! (entrance)"
              end
            end

            self.current_connection = conn
          end

          yield(conn)
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

    def execute(command, params = nil)
      sql =
        case command
        when Symbol then SQL[command]
        when String then command
        else raise Error, "Bad command! #{command.inspect}"
        end

      params = convert_params(params) if params
      start  = Time.now
      result = execute_sql(sql, params)

      Que.internal_log :pool_execute, self do
        {
          # TODO: backend_pid: conn.backend_pid,
          command:   command,
          params:    params,
          elapsed:   Time.now - start,
          ntuples:   result.ntuples,
        }
      end

      convert_result(result)
    end

    def in_transaction?
      checkout { |conn| conn.transaction_status != ::PG::PQTRANS_IDLE }
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

    def convert_params(params)
      params.map do |param|
        case param
          # The pg gem unfortunately doesn't convert fractions of time
          # instances, so cast them to a string.
          when Time then param.strftime('%Y-%m-%d %H:%M:%S.%6N %z')
          when Array, Hash then JSON.dump(param)
          else param
        end
      end
    end

    def execute_sql(sql, params)
      checkout do |conn|
        # Some PG versions dislike being passed an empty or nil params argument.
        if params && !params.empty?
          conn.async_exec(sql, params)
        else
          conn.async_exec(sql)
        end
      end
    end

    # Procs used to convert strings from PG into Ruby types.
    CAST_PROCS = {
      # Boolean
      16   => 't'.method(:==),
      # Timestamp with time zone
      1184 => Time.method(:parse),
    }

    # JSON, JSONB
    CAST_PROCS[114] = CAST_PROCS[3802] = -> (j) { Que.deserialize_json(j) }

    # Integer, bigint, smallint
    CAST_PROCS[23] = CAST_PROCS[20] = CAST_PROCS[21] = proc(&:to_i)

    CAST_PROCS.freeze

    def convert_result(result)
      output = result.to_a

      result.fields.each_with_index do |field, index|
        symbol = field.to_sym

        if converter = CAST_PROCS[result.ftype(index)]
          output.each do |hash|
            value = hash.delete(field)
            value = converter.call(value) if value
            hash[symbol] = value
          end
        else
          output.each do |hash|
            hash[symbol] = hash.delete(field)
          end
        end
      end

      output
    end
  end
end
