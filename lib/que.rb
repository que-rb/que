module Que
  autoload :Adapters, 'que/adapters/base'
  autoload :Job,      'que/job'
  autoload :SQL,      'que/sql'
  autoload :Version,  'que/version'
  autoload :Worker,   'que/worker'

  class << self
    attr_accessor :logger, :error_handler
    attr_writer :adapter

    def adapter
      @adapter || raise("Que connection not established!")
    end

    def connection=(connection)
      self.adapter = if connection.to_s == 'ActiveRecord'
        Adapters::ActiveRecord.new
      else
        case connection.class.to_s
          when 'Sequel::Postgres::Database' then Adapters::Sequel.new(connection)
          when 'ConnectionPool'             then Adapters::ConnectionPool.new(connection)
          when 'PG::Connection'             then Adapters::PG.new(connection)
          when 'NilClass'                   then connection
          else raise "Que connection not recognized: #{connection.inspect}"
        end
      end
    end

    def create!
      execute SQL[:create_table]
    end

    def drop!
      execute "DROP TABLE que_jobs"
    end

    def clear!
      execute "DELETE FROM que_jobs"
    end

    def execute(command, *args)
      case command
        when Symbol then adapter.execute_prepared(command, *args)
        when String then adapter.execute(command, *args)
      end
    end

    def log(level, text)
      logger.send level, "[Que] #{text}" if logger
    end

    # Copy some of the Worker class' config methods here for convenience.
    [:mode, :mode=, :worker_count=, :sleep_period, :sleep_period=, :stop!].each do |meth|
      define_method(meth) { |*args| Worker.send(meth, *args) }
    end
  end
end

require 'que/railtie' if defined? Rails::Railtie
