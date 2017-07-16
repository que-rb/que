# frozen_string_literal: true

module Que
  module SQL
    class << self
      def register_sql_statement(name, sql)
        if sql_statements.has_key?(name)
          raise Error, "Duplicate SQL statement declaration! (#{name})"
        end

        # Strip excess whitespace from SQL statements so the logs are cleaner.
        sql_statements[name] = sql.strip.gsub(/\s+/, ' ').freeze
      end

      def fetch_sql(name)
        sql_statements.fetch(name) do
          raise Error,
            "#{name.inspect} doesn't correspond to a known SQL statement!"
        end
      end

      private

      def sql_statements
        @sql_statements ||= {}
      end
    end
  end
end
