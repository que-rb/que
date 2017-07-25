# frozen_string_literal: true

# A wrapper around connection objects, to improve the query API a bit.

require 'time' # For Time.parse

module Que
  class Connection
    extend Forwardable

    attr_reader :pg

    def_delegators :pg, :backend_pid, :wait_for_notify

    def initialize(pg:)
      @pg = pg
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

      Que.internal_log :connection_execute, self do
        {
          backend_pid: pg.backend_pid,
          command:     command,
          params:      params,
          elapsed:     Time.now - start,
          ntuples:     result.ntuples,
        }
      end

      convert_result(result)
    end

    def next_notification
      pg.notifies
    end

    def drain_notifications
      loop { break if next_notification.nil? }
    end

    def in_transaction?
      pg.transaction_status != ::PG::PQTRANS_IDLE
    end

    private

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
      # Some PG versions dislike being passed an empty or nil params argument.
      if params && !params.empty?
        pg.async_exec(sql, params)
      else
        pg.async_exec(sql)
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
