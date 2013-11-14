require 'que/version'

module Que
  autoload :Adapter, 'que/adapter'
  autoload :Job,     'que/job'

  autoload :ActiveRecord,   'que/adapters/active_record'
  autoload :ConnectionPool, 'que/adapters/connection_pool'
  autoload :PG,             'que/adapters/pg'
  autoload :Sequel,         'que/adapters/sequel'

  root = File.expand_path '..', File.dirname(__FILE__)

  CreateTableSQL = File.read(File.join(root, '/sql/create.sql')).freeze
  LockSQL        = File.read(File.join(root, '/sql/lock.sql')).freeze

  class << self
    def connection=(connection)
      @connection = if connection.to_s == "ActiveRecord"
        Que::ActiveRecord.new
      elsif connection.class.to_s == "Sequel::Postgres::Database"
        Que::Sequel.new(connection)
      elsif connection.class.to_s == "PG::Connection"
        Que::PG.new(connection)
      elsif connection.class.to_s == "ConnectionPool"
        Que::ConnectionPool.new(connection)
      elsif connection.nil?
        connection
      else
        raise "Que connection not recognized: #{connection.inspect}"
      end
    end

    def connection
      @connection || raise("Que connection not established!")
    end

    def create!
      execute CreateTableSQL
    end

    def drop!
      execute "DROP TABLE que_jobs"
    end

    def clear!
      execute "DELETE FROM que_jobs"
    end

    def execute(*args)
      connection.execute(*args)
    end
  end
end
