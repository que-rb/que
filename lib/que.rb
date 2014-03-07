require 'forwardable'
require 'socket' # For Socket.gethostname

module Que
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
  require_relative 'que/sql'
  require_relative 'que/version'
  require_relative 'que/worker'

  class << self
    extend Forwardable

    attr_accessor :logger, :error_handler
    attr_writer :pool, :log_formatter
    attr_reader :mode, :locker

    def connection=(connection)
      warn "Que.connection= has been deprecated and will be removed in version 1.1.0. Please use Que.connection_proc= instead."

      self.connection_proc = if connection.to_s == 'ActiveRecord'
        proc { |&block| ActiveRecord::Base.connection_pool.with_connection { |conn| block.call(conn.raw_connection) } }
      else
        case connection.class.to_s
          when 'Sequel::Postgres::Database' then connection.method(:synchronize)
          when 'ConnectionPool'             then connection.method(:with)
          when 'PG::Connection'             then raise "Que now requires a connection pool and can no longer use a plain PG::Connection."
          when 'NilClass'                   then connection
          else raise "Que connection not recognized: #{connection.inspect}"
        end
      end
    end

    def connection_proc=(connection_proc)
      @pool = connection_proc && Pool.new(connection_proc)
    end

    def pool
      @pool || raise("Que connection not established!")
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

      if logger && output = log_formatter.call(data)
        logger.send level, output
      end
    end

    def log_formatter
      @log_formatter ||= JSON_MODULE.method(:dump)
    end

    %w(wake_interval wake_interval= wake! wake_all! worker_count worker_count=).each do |meth|
      define_method meth do |*args|
        warn "Que.#{meth} no longer serves a purpose and will be removed entirely in version 1.1.0."
        nil
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
          raise "Unknown Que mode: #{mode.inspect}"
        end

        log :event => 'mode_change', :value => mode.to_s
        @mode = mode
      end
    end

    # Copy some commonly-used methods here, for convenience.
    def_delegators :pool, :execute, :checkout, :in_transaction?
    def_delegators Job, :enqueue
    def_delegators Migrations, :db_version, :migrate!
  end
end

require 'que/railtie' if defined? Rails::Railtie
