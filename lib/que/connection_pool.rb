# frozen_string_literal: true

# A wrapper around whatever connection pool we're using.

require 'time' # For Time.parse

module Que
  class ConnectionPool
    def initialize(&block)
      @connection_proc = block
    end

    def checkout(&block)
      @connection_proc.call(&block)
    end

    def execute(command, params = [])
      sql = nil
      log = {
        level: :debug,
        params: params,
      }

      case command
      when Symbol
        sql = SQL[command] || raise(Error, "Bad command! #{command.inspect}")
        log[:event] = :execute
        log[:command] = command
      when String
        sql = command
        log[:event] = :execute_sql
        log[:sql] = sql
      else
        raise Error, "Bad command! #{command.inspect}"
      end

      p = convert_params(params)

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
      args = params.empty? ? [sql] : [sql, params]
      checkout { |conn| conn.async_exec(*args) }
    end

    # Procs used to convert strings from PG into Ruby types.
    CAST_PROCS = {
      # Boolean
      16   => 't'.method(:==),
      # JSON
      114  => proc { |json| Que.json_deserializer.call(json) },
      # Timestamp with time zone
      1184 => Time.method(:parse),
    }

    # Integer, bigint, smallint
    CAST_PROCS[23] = CAST_PROCS[20] = CAST_PROCS[21] = proc(&:to_i)

    CAST_PROCS.freeze

    def convert_result(result)
      output = result.to_a

      result.fields.each_with_index do |field, index|
        symbol = field.to_sym
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
