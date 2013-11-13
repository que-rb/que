require 'que/version'

module Que
  autoload :Adapter, 'que/adapter'
  autoload :Job,     'que/job'
  autoload :SQL,     'que/sql'

  autoload :ActiveRecord, 'que/adapters/active_record'
  autoload :PG,           'que/adapters/pg'
  autoload :Sequel,       'que/adapters/sequel'

  class << self
    def connection=(connection)
      @connection = if connection.to_s == "ActiveRecord"
        Que::ActiveRecord.new
      elsif connection.class.to_s == "Sequel::Postgres::Database"
        Que::Sequel.new(connection)
      elsif connection.class.to_s == "PG::Connection"
        Que::PG.new(connection)
      else
        raise "Que connection not recognized: #{connection.inspect}"
      end
    end

    def connection
      @connection ||= if defined?(::ActiveRecord::Base)
        Que::ActiveRecord.new
      else
        raise "Que connection not established!"
      end
    end

    def create!
      execute SQL.create_sql
    end

    def drop!
      execute SQL.drop_sql
    end

    def clear!
      execute SQL.clear_sql
    end

    def execute(*args)
      connection.execute(*args)
    end
  end
end
