require 'forwardable'
require 'socket' # For Socket.gethostname

module Que
  class Error < StandardError; end

  begin
    require 'multi_json'
    JSON_MODULE = MultiJson
  rescue LoadError
    require 'json'
    JSON_MODULE = JSON
  end

  require_relative 'que/job'
  require_relative 'que/job_queue'
  require_relative 'que/locker'
  require_relative 'que/migrations'
  require_relative 'que/pool'
  require_relative 'que/recurring_job'
  require_relative 'que/sql'
  require_relative 'que/version'
  require_relative 'que/worker'

  class << self
    extend Forwardable

    attr_accessor :logger, :error_handler
    attr_writer :pool, :log_formatter, :logger
    attr_reader :mode, :locker

    def connection=(connection)
      self.connection_proc =
        if connection.to_s == 'ActiveRecord'
          proc { |&block| ActiveRecord::Base.connection_pool.with_connection { |conn| block.call(conn.raw_connection) } }
        else
          case connection.class.to_s
            when 'Sequel::Postgres::Database' then connection.method(:synchronize)
            when 'ConnectionPool'             then connection.method(:with)
            when 'Pond'                       then connection.method(:checkout)
            when 'PG::Connection'             then raise "Que now requires a connection pool and can no longer use a plain PG::Connection."
            when 'NilClass'                   then connection
            else raise Error, "Que connection not recognized: #{connection.inspect}"
          end
        end
    end

    def connection_proc=(connection_proc)
      @pool = connection_proc && Pool.new(&connection_proc)
    end

    def pool
      @pool || raise(Error, "Que connection not established!")
    end

    def clear!
      execute "DELETE FROM que_jobs"
    end

    def job_stats
      execute :job_stats
    end

    def job_states
      execute :job_states
    end

    # Have to support create! and drop! in old migrations. They just created
    # and dropped the bare table.
    def create!
      migrate! :version => 1
    end

    def drop!
      migrate! :version => 0
    end

    def log(data)
      level = data.delete(:level) || :info
      data = {:lib => 'que', :hostname => Socket.gethostname, :pid => Process.pid, :thread => Thread.current.object_id}.merge(data)

      if (l = logger) && output = log_formatter.call(data)
        l.send level, output
      end
    end

    def logger
      @logger.respond_to?(:call) ? @logger.call : @logger
    end

    def log_formatter
      @log_formatter ||= JSON_MODULE.method(:dump)
    end

    # A helper method to manage transactions, used mainly by the migration
    # system. It's available for general use, but if you're using an ORM that
    # provides its own transaction helper, be sure to use that instead, or the
    # two may interfere with one another.
    def transaction
      pool.checkout do
        if pool.in_transaction?
          yield
        else
          begin
            execute "BEGIN"
            yield
          rescue => error
            raise
          ensure
            # Handle a raised error or a killed thread.
            if error || Thread.current.status == 'aborting'
              execute "ROLLBACK"
            else
              execute "COMMIT"
            end
          end
        end
      end
    end

    def mode=(mode)
      if @mode != mode
        case mode
        when :async
          @locker = Locker.new
        when :sync, :off
          if @locker
            @locker.stop
            @locker = nil
          end
        else
          raise Error, "Unknown Que mode: #{mode.inspect}"
        end

        log :level => :debug, :event => 'mode_change', :value => mode.to_s
        @mode = mode
      end
    end

    def symbolize_recursively!(object)
      case object
      when Hash
        object.keys.each do |key|
          object[key.to_sym] = symbolize_recursively!(object.delete(key))
        end
        object
      when Array
        object.map! { |e| symbolize_recursively!(e) }
      else
        object
      end
    end

    # Copy some commonly-used methods here, for convenience.
    def_delegators :pool, :execute, :checkout, :in_transaction?
    def_delegators Job, :enqueue
    def_delegators Migrations, :db_version, :migrate!
  end
end
