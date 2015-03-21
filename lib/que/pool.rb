# A wrapper around whatever connection pool we're using.

require 'time' # For Time.parse

module Que
  class Pool
    def initialize(&block)
      @connection_proc = block
    end

    def checkout(&block)
      @connection_proc.call(&block)
    end

    def execute(command, params = [])
      sql = case command
            when Symbol then SQL[command] || raise("Bad command! #{command.inspect}")
            when String then command
            else raise("Bad command! #{command.inspect}")
            end

      p = convert_params(params)
      result = checkout{execute_sql(sql, p)}
      convert_result(result)
    end

    def in_transaction?
      checkout { |conn| conn.transaction_status != ::PG::PQTRANS_IDLE }
    end

    private

    def convert_params(params)
      params.map do |param|
        case param
          # The pg gem unfortunately doesn't convert fractions of time instances, so cast them to a string.
          when Time then param.strftime('%Y-%m-%d %H:%M:%S.%6N %z')
          when Array, Hash then JSON_MODULE.dump(param)
          else param
        end
      end
    end

    def execute_sql(sql, params)
      Que.log :level => :debug, :event => :execute_sql, :sql => sql, :params => params
      args = params.empty? ? [sql] : [sql, params] # Work around JRuby bug.
      checkout { |conn| conn.async_exec(*args) }
    end

    # Procs used to convert strings from PG into Ruby types.
    CAST_PROCS = {
      16   => 't'.method(:==),                                                    # Boolean.
      114  => proc { |json| Que.symbolize_recursively!(JSON_MODULE.load(json)) }, # JSON.
      1184 => Time.method(:parse)                                                 # Timestamp with time zone.
    }
    CAST_PROCS[23] = CAST_PROCS[20] = CAST_PROCS[21] = proc(&:to_i) # Integer, bigint, smallint.
    CAST_PROCS.freeze

    def convert_result(result)
      output = result.to_a

      result.fields.each_with_index do |field, index|
        symbol = field.to_sym
        converter = CAST_PROCS[result.ftype(index)]

        output.each do |hash|
          if (value = hash.delete(field)) && converter
            value = converter.call(value)
          end

          hash[symbol] = value
        end
      end

      output
    end
  end
end
