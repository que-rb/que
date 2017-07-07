# frozen_string_literal: true

# A wrapper around whatever connection pool we're using.

require 'time' # For Time.parse

module Que
  class ConnectionPool
    def initialize(&block)
      @connection_proc = block
      @checked_out = Set.new
      @mutex = Mutex.new
    end

    def checkout
      @connection_proc.call do |conn|
        original  = Thread.current[:que_connection]
        was_added = nil

        begin
          if original.nil?
            @mutex.synchronize do
              was_added = @checked_out.add?(conn.object_id)
              unless was_added
                raise Error, "Connection pool did not synchronize access properly!"
              end
            end
          end

          if original
            if original.object_id != conn.object_id
              raise Error, "Connection pool is not reentrant!"
            end
          else
            Thread.current[:que_connection] = conn
          end

          yield(conn)
        ensure
          if original.nil?
            Thread.current[:que_connection] = nil
            if was_added
              @mutex.synchronize do
                Que.assert(@checked_out.delete?(conn.object_id))
              end
            end
          end
        end
      end
    end

    def execute(command, params = nil)
      sql = nil
      log = {level: :debug}

      case command
      when Symbol
        sql = SQL[command] || raise(Error, "Bad command! #{command.inspect}")
        log[:event]   = :execute
        log[:command] = command
      when String
        sql = command
        log[:event] = :execute_sql
        log[:sql]   = sql
      else
        raise Error, "Bad command! #{command.inspect}"
      end

      if params
        log[:params] = params
        p = convert_params(params)
      end

      t = Time.now
      result = execute_sql(sql, p)
      log[:elapsed] = Time.now - t

      Que.log(log)

      convert_result(result)
    end

    def in_transaction?
      checkout { |conn| conn.transaction_status != ::PG::PQTRANS_IDLE }
    end

    private

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
    CAST_PROCS[114] = CAST_PROCS[3802] =
      -> (json) { Que.deserialize_json(json) }

    # Integer, bigint, smallint
    CAST_PROCS[23] = CAST_PROCS[20] = CAST_PROCS[21] = proc(&:to_i)

    CAST_PROCS.freeze

    def convert_result(result)
      output = result.to_a

      result.fields.each_with_index do |field, index|
        symbol    = field.to_sym
        converter = CAST_PROCS[result.ftype(index)]

        output.each do |hash|
          value = hash.delete(field)

          if value && converter
            value = converter.call(value)
          end

          hash[symbol] = value
        end
      end

      output
    end
  end
end
