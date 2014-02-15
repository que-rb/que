require 'time' # For Time.parse.

module Que
  module Adapters
    autoload :ActiveRecord,   'que/adapters/active_record'
    autoload :ConnectionPool, 'que/adapters/connection_pool'
    autoload :Pond,           'que/adapters/pond'
    autoload :Sequel,         'que/adapters/sequel'

    class Base
      def initialize(thing = nil)
        @prepared_statements = {}
      end

      # The only method that adapters really need to implement. Should lock a
      # PG::Connection (or something that acts like a PG::Connection) so that
      # no other threads are using it and yield it to the block. Should also
      # be re-entrant.
      def checkout(&block)
        raise NotImplementedError
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

        cast_result \
          case command
            when Symbol then execute_prepared(command, params)
            when String then execute_sql(command, params)
          end
      end

      def in_transaction?
        checkout { |conn| conn.transaction_status != ::PG::PQTRANS_IDLE }
      end

      def wait_for_json(timeout = nil)
        checkout do |conn|
          conn.wait_for_notify(timeout) do |_, _, payload|
            return INDIFFERENTIATOR.call(JSON_MODULE.load(payload))
          end
        end
      end

      def drain_notifications
        checkout { |conn| {} while conn.notifies }
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

      HASH_DEFAULT_PROC = proc { |hash, key| hash[key.to_s] if Symbol === key }

      INDIFFERENTIATOR = proc do |object|
        case object
        when Array
          object.each(&INDIFFERENTIATOR)
        when Hash
          object.default_proc = HASH_DEFAULT_PROC
          object.each { |key, value| object[key] = INDIFFERENTIATOR.call(value) }
          object
        else
          object
        end
      end

      CAST_PROCS = {}

      # Integer, bigint, smallint:
      CAST_PROCS[23] = CAST_PROCS[20] = CAST_PROCS[21] = proc(&:to_i)

      # Timestamp with time zone.
      CAST_PROCS[1184] = Time.method(:parse)

      # JSON.
      CAST_PROCS[114] = JSON_MODULE.method(:load)

      # Boolean:
      CAST_PROCS[16] = 't'.method(:==)

      def cast_result(result)
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

        if result.first.respond_to?(:with_indifferent_access)
          output.map(&:with_indifferent_access)
        else
          output.each(&INDIFFERENTIATOR)
        end
      end
    end
  end
end
