require 'que/version'

module Que
  autoload :Adapter, 'que/adapter'
  autoload :Job,     'que/job'
  autoload :SQL,     'que/sql'

  autoload :ActiveRecord,   'que/adapters/active_record'
  autoload :ConnectionPool, 'que/adapters/connection_pool'
  autoload :PG,             'que/adapters/pg'
  autoload :Sequel,         'que/adapters/sequel'

  root = File.expand_path '..', File.dirname(__FILE__)

  CreateTableSQL = File.read(File.join(root, '/sql/create.sql')).freeze

  class << self
    attr_accessor :logger, :error_handler

    def log(level, text)
      logger.send level, text if logger
    end

    def connection=(connection)
      @connection = if connection.to_s == 'ActiveRecord'
        Que::ActiveRecord.new
      else
        case connection.class.to_s
          when 'Sequel::Postgres::Database' then Que::Sequel.new(connection)
          when 'ConnectionPool'             then Que::ConnectionPool.new(connection)
          when 'PG::Connection'             then Que::PG.new(connection)
          when 'NilClass'                   then connection
          else raise "Que connection not recognized: #{connection.inspect}"
        end
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

    def execute(command, *args)
      case command
        when Symbol then connection.execute_prepared(command, *args)
        when String then connection.execute(command, *args)
      end
    end
  end
end
