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

      result = if Symbol === command
        if Que.use_prepared_statements
          execute_prepared(command, params)
        else
          execute_sql(SQL[command], params)
        end
      else
        execute_sql(command, params)
      end

      process_result(result)
    end

    def in_transaction?
      checkout { |conn| conn.transaction_status != ::PG::PQTRANS_IDLE }
    end

    private

    def execute_sql(sql, params)
      Que.log :level => :debug, :event => :execute_sql, :sql => sql, :params => params
      args = params.empty? ? [sql] : [sql, params]
      checkout { |conn| conn.async_exec(*args) }
    end

    def execute_prepared(name, params)
      Que.log :level => :debug, :event => :execute_statement, :statement => name, :params => params
      checkout do |conn|
        statements = @prepared_statements[conn] ||= {}

        unless statements[name]
          conn.prepare("que_#{name}", SQL[name])
          statements[name] = true
        end

        conn.exec_prepared("que_#{name}", params)
      end
    end

    # Procs used to convert strings from PG into Ruby types.
    CAST_PROCS = {
      16   => 't'.method(:==),           # Boolean.
      114  => JSON_MODULE.method(:load), # JSON.
      1184 => Time.method(:parse)        # Timestamp with time zone.
    }
    CAST_PROCS[23] = CAST_PROCS[20] = CAST_PROCS[21] = proc(&:to_i) # Integer, bigint, smallint.
    CAST_PROCS.freeze

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

      indifferentiate(output)
    end

    # Make hashes indifferently-accessible.
    def indifferentiate(object)
      case object
      when Hash
        if object.respond_to?(:with_indifferent_access)
          object.with_indifferent_access
        else
          object.default_proc = HASH_DEFAULT_PROC
          object.each { |key, value| object[key] = indifferentiate(value) }
        end
      when Array
        object.map! { |element| indifferentiate(element) }
      else
        object
      end
    end

    HASH_DEFAULT_PROC = proc { |hash, key| hash[key.to_s] if Symbol === key }
  end
end
