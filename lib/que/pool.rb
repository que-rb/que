# A wrapper around whatever connection pool we're using.

require 'time' # For Time.parse

module Que
  class Pool
    def initialize(&block)
      @connection_proc = block
      @prepared_statements = {}
    end

    def checkout(&block)
      @connection_proc.call(&block)
    end

    def execute(command, params = [])
      checkout { convert_result(execute_command(command, convert_params(params))) }
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

    def execute_command(command, params)
      case command
      when Symbol
        # Prepared statement errors have the potential to cancel the entire
        # transaction, so if we're in one, err on the side of safety.
        if Que.use_prepared_statements && !in_transaction?
          execute_prepared(command, params)
        else
          execute_sql(SQL[command], params)
        end
      when String
        execute_sql(command, params)
      else
        raise "Command not recognized! #{command.inspect}"
      end
    end

    def execute_sql(sql, params)
      Que.log :level => :debug, :event => :execute_sql, :sql => sql, :params => params
      args = params.empty? ? [sql] : [sql, params] # Work around JRuby bug.
      checkout { |conn| conn.async_exec(*args) }
    end

    def execute_prepared(name, params)
      Que.log :level => :debug, :event => :execute_statement, :statement => name, :params => params

      checkout do |conn|
        statements = @prepared_statements[conn] ||= {}

        begin
          unless statements[name]
            conn.prepare("que_#{name}", SQL[name])
            prepared_just_now = statements[name] = true
          end

          conn.exec_prepared("que_#{name}", params)
        rescue ::PG::InvalidSqlStatementName => error
          # Reconnections on ActiveRecord can cause the same connection
          # objects to refer to new backends, so recover as well as we can.

          unless prepared_just_now
            Que.log :level => :warn, :event => :reprepare_statement, :name => name
            statements[name] = false
            retry
          end

          raise error
        end
      end
    end

    symbolize_recursively = proc do |object|
      case object
      when Hash
        object.keys.each do |key|
          object[key.to_sym] = symbolize_recursively.call(object.delete(key))
        end
        object
      when Array
        object.map!(&symbolize_recursively)
      else
        object
      end
    end

    # Procs used to convert strings from PG into Ruby types.
    CAST_PROCS = {
      16   => 't'.method(:==),                                                    # Boolean.
      114  => proc { |json| symbolize_recursively.call(JSON_MODULE.load(json)) }, # JSON.
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
