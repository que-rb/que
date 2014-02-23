# A wrapper around whatever connection pool we're using.

require 'time' # For Time.parse

module Que
  class Pool
    def initialize(connection_proc)
      @connection_proc = connection_proc
      @prepared_statements = {}
    end

    def checkout(&block)
      @connection_proc.call(&block)
    end

    def execute(command, params = [])
      params = params.map do |param|
        case param
          # The pg gem unfortunately doesn't convert fractions of time instances, so cast them to a string.
          when Time then param.strftime("%Y-%m-%d %H:%M:%S.%6N %z")
          when Array, Hash then JSON_MODULE.dump(param)
          else param
        end
      end

      process_result \
        case command
          when Symbol then execute_prepared(command, params)
          when String then execute_sql(command, params)
        end
    end

    def in_transaction?
      checkout { |conn| conn.transaction_status != ::PG::PQTRANS_IDLE }
    end

    private

    def execute_sql(sql, params)
      args = params.empty? ? [sql] : [sql, params]
      checkout { |conn| conn.async_exec(*args) }
    end

    def execute_prepared(name, params)
      checkout do |conn|
        statements = @prepared_statements[conn] ||= {}

        unless statements[name]
          conn.prepare("que_#{name}", SQL[name])
          statements[name] = true
        end

        conn.exec_prepared("que_#{name}", params)
      end
    end

    CAST_PROCS = {}

    # Integer, bigint, smallint.
    CAST_PROCS[23] = CAST_PROCS[20] = CAST_PROCS[21] = proc(&:to_i)

    # Timestamp with time zone.
    CAST_PROCS[1184] = Time.method(:parse)

    # JSON.
    CAST_PROCS[114] = JSON_MODULE.method(:load)

    # Boolean.
    CAST_PROCS[16] = 't'.method(:==)

    def process_result(result)
      output = result.to_a

      result.fields.each_with_index do |field, index|
        if converter = CAST_PROCS[result.ftype(index)]
          output.each do |hash|
            unless (value = hash[field]).nil?
              hash[field] = converter.call(value)
            end
          end
        end
      end

      Que.indifferentiate(output)
    end
  end
end
