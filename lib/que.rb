require 'socket' # For hostname

module Que
  autoload :Adapters,   'que/adapters/base'
  autoload :Job,        'que/job'
  autoload :Migrations, 'que/migrations'
  autoload :SQL,        'que/sql'
  autoload :Version,    'que/version'
  autoload :Worker,     'que/worker'

  begin
    require 'multi_json'
    JSON_MODULE = MultiJson
  rescue LoadError
    require 'json'
    JSON_MODULE = JSON
  end

  class << self
    attr_accessor :logger, :error_handler
    attr_writer :adapter, :log_formatter

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

    # Have to support create! and drop! in old migrations. They just created
    # and dropped the bare table.
    def create!
      migrate! :version => 1
    end

    def drop!
      migrate! :version => 0
    end

    def migrate!(version = {:version => Migrations::CURRENT_VERSION})
      Migrations.migrate!(version)
    end

    def db_version
      Migrations.db_version
    end

    def clear!
      execute "DELETE FROM que_jobs"
    end

    def job_stats
      execute :job_stats
    end

    def worker_states
      execute :worker_states
    end

    def execute(command, *args)
      indifferentiate case command
                        when Symbol then adapter.execute_prepared(command, *args)
                        when String then adapter.execute(command, *args)
                      end.to_a
    end

    def log(data)
      level = data.delete(:level) || :info
      data = {:lib => 'que', :hostname => Socket.gethostname, :thread => Thread.current.object_id}.merge(data)

      if logger && output = log_formatter.call(data)
        logger.send level, output
      end
    end

    # Give us a cleaner interface when specifying a job_class as a string.
    def enqueue(*args)
      Job.enqueue(*args)
    end

    def log_formatter
      @log_formatter ||= JSON_MODULE.method(:dump)
    end

    # Helper for making hashes indifferently-accessible, even when nested
    # within each other and within arrays.
    def indifferentiate(object)
      case object
      when Hash
        h = if {}.respond_to?(:with_indifferent_access) # Better support for Rails.
              {}.with_indifferent_access
            else
              Hash.new { |hash, key| hash[key.to_s] if Symbol === key }
            end

        object.each { |k, v| h[k] = indifferentiate(v) }
        h
      when Array
        object.map { |v| indifferentiate(v) }
      else
        object
      end
    end

    # Copy some of the Worker class' config methods here for convenience.
    [:mode, :mode=, :worker_count, :worker_count=, :wake_interval, :wake_interval=, :wake!, :wake_all!].each do |meth|
      define_method(meth) { |*args| Worker.send(meth, *args) }
    end
  end
end

require 'que/railtie' if defined? Rails::Railtie
