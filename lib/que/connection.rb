# frozen_string_literal: true

# A simple wrapper class around connections that basically just improves the
# query API a bit. Currently, our connection pool wrapper discards these
# connection wrappers once the connection is returned to the source connection
# pool, so this class isn't currently suitable for storing data about the
# connection long-term (like what statements it has prepared, for example).

# If we wanted to do that, we'd probably need to sneak a reference to the
# wrapper into the PG::Connection object itself, by just setting a instance
# variable that's something namespaced and hopefully safe, like
# `@que_connection_wrapper`. It's a bit ugly, but it should ensure that we don't
# cause any memory leaks in esoteric setups where one-off connections are being
# established and then garbage-collected.

require 'time' # For Time.parse
require 'set'

module Que
  class Connection
    extend Forwardable

    attr_reader :wrapped_connection

    def_delegators :wrapped_connection, :backend_pid, :wait_for_notify

    class << self
      def wrap(conn)
        case conn
        when self
          conn
        when PG::Connection
          if conn.instance_variable_defined?(:@que_wrapper)
            conn.instance_variable_get(:@que_wrapper)
          else
            conn.instance_variable_set(:@que_wrapper, new(conn))
          end
        else
          raise Error, "Unsupported input for Connection.wrap: #{conn.class}"
        end
      end
    end

    def initialize(connection)
      @wrapped_connection = connection
      @prepared_statements = Set.new
    end

    def execute(command, params = [])
      sql =
        case command
        when Symbol then SQL[command]
        when String then command
        else raise Error, "Bad command! #{command.inspect}"
        end

      params = convert_params(params)

      result =
        Que.run_sql_middleware(sql, params) do
          # Some versions of the PG gem dislike an empty/nil params argument.
          if params.empty?
            wrapped_connection.async_exec(sql)
          else
            wrapped_connection.async_exec(sql, params)
          end
        end

      Que.internal_log :connection_execute, self do
        {
          backend_pid: backend_pid,
          command:     command,
          params:      params,
          ntuples:     result.ntuples,
        }
      end

      convert_result(result)
    end

    def execute_prepared(command, params = nil)
      Que.assert(Symbol, command)

      if !Que.use_prepared_statements || in_transaction?
        return execute(command, params)
      end

      name = "que_#{command}"

      begin
        unless @prepared_statements.include?(command)
          wrapped_connection.prepare(name, SQL[command])
          @prepared_statements.add(command)
          prepared_just_now = true
        end

        convert_result(
          wrapped_connection.exec_prepared(name, params)
        )
      rescue ::PG::InvalidSqlStatementName => error
        # Reconnections on ActiveRecord can cause the same connection
        # objects to refer to new backends, so recover as well as we can.

        unless prepared_just_now
          Que.log level: :warn, event: :reprepare_statement, command: command
          @prepared_statements.delete(command)
          retry
        end

        raise error
      end
    end

    def next_notification
      wrapped_connection.notifies
    end

    def drain_notifications
      loop { break if next_notification.nil? }
    end

    def in_transaction?
      wrapped_connection.transaction_status != ::PG::PQTRANS_IDLE
    end

    private

    def convert_params(params)
      params.map do |param|
        case param
        when Time
          # The pg gem unfortunately doesn't convert fractions of time
          # instances, so cast them to a string.
          param.strftime('%Y-%m-%d %H:%M:%S.%6N %z')
        when Array, Hash
          # Handle JSON.
          Que.serialize_json(param)
        else
          param
        end
      end
    end

    # Procs used to convert strings from Postgres into Ruby types.
    CAST_PROCS = {
      # Boolean
      16 => -> (value) {
        case value
        when String then value == 't'.freeze
        else !!value
        end
      },

      # Timestamp with time zone
      1184 => -> (value) {
        case value
        when Time then value
        when String then Time.parse(value)
        else raise "Unexpected time class: #{value.class} (#{value.inspect})"
        end
      }
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
