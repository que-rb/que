# frozen_string_literal: true

require 'forwardable'
require 'socket' # For Socket.gethostname

module Que
  CURRENT_HOSTNAME = Socket.gethostname.freeze
  DEFAULT_QUEUE    = 'default'.freeze
  TIME_REGEX       = /\A\d{4}\-\d{2}\-\d{2}T\d{2}:\d{2}:\d{2}.\d{6}Z\z/
  CONFIG_MUTEX     = Mutex.new
  MAXIMUM_PRIORITY = 32767

  class Error < StandardError; end

  # Store SQL strings frozen, with squashed whitespace so logs read better.
  SQL = {}
  def SQL.[]=(k,v); super(k, v.strip.gsub(/\s+/, ' ').freeze); end

  # Load up modules that allow registration before modules that use it.
  require_relative 'que/listener'

  # Load utilities before main logic that will use them.
  require_relative 'que/utils/assertions'
  require_relative 'que/utils/constantization'
  require_relative 'que/utils/error_notification'
  require_relative 'que/utils/freeze'
  require_relative 'que/utils/introspection'
  require_relative 'que/utils/json_serialization'
  require_relative 'que/utils/logging'
  require_relative 'que/utils/middleware'
  require_relative 'que/utils/queue_management'
  require_relative 'que/utils/ruby2_keywords'
  require_relative 'que/utils/transactions'

  require_relative 'que/version'

  require_relative 'que/connection'
  require_relative 'que/connection_pool'
  require_relative 'que/job_methods'
  require_relative 'que/job'
  require_relative 'que/job_buffer'
  require_relative 'que/locker'
  require_relative 'que/metajob'
  require_relative 'que/migrations'
  require_relative 'que/poller'
  require_relative 'que/result_queue'
  require_relative 'que/worker'

  class << self
    attr_writer :default_queue
  end

  self.default_queue = nil

  class << self
    include Utils::Assertions
    include Utils::Constantization
    include Utils::ErrorNotification
    include Utils::Freeze
    include Utils::Introspection
    include Utils::JSONSerialization
    include Utils::Logging
    include Utils::Middleware
    include Utils::QueueManagement
    include Utils::Ruby2Keywords
    include Utils::Transactions

    extend Forwardable

    # Copy some commonly-used methods here, for convenience.
    def_delegators :pool, :execute, :checkout, :in_transaction?
    def_delegators Job, :enqueue, :bulk_enqueue, :run_synchronously, :run_synchronously=
    def_delegators Migrations, :db_version, :migrate!

    # Global configuration logic.
    attr_accessor :use_prepared_statements

    def default_queue
      @default_queue || DEFAULT_QUEUE
    end

    def server?
      !defined?(Que::CommandLineInterface).nil?
    end

    # Support simple integration with many common connection pools.
    def connection=(conn)
      self.connection_proc =
        if conn.to_s == 'ActiveRecord'
          # Load and setup AR compatibility.
          require_relative 'que/active_record/connection'
          m = Que::ActiveRecord::Connection::JobMiddleware
          job_middleware << m unless job_middleware.include?(m)
          Que::ActiveRecord::Connection.method(:checkout)
        else
          case conn.class.to_s
          when 'Sequel::Postgres::Database' then conn.method(:synchronize)
          when 'Pond'                       then conn.method(:checkout)
          when 'ConnectionPool'             then conn.method(:with)
          when 'NilClass'                   then conn
          else raise Error, "Unsupported connection: #{conn.class}"
          end
        end
    end

    # Integrate Que with any connection pool by passing it a reentrant block
    # that locks and yields a Postgres connection.
    def connection_proc=(connection_proc)
      @pool = connection_proc && ConnectionPool.new(&connection_proc)
    end

    # How to actually access Que's established connection pool.
    def pool
      @pool || raise(Error, "Que connection not established!")
    end

    # Set the current pool. Helpful for specs, but probably shouldn't be used
    # generally.
    attr_writer :pool
  end

  # Set config defaults.
  self.use_prepared_statements = true
end

# Load Rails features as appropriate.
require_relative 'que/rails/railtie'         if defined?(::Rails::Railtie)
require_relative 'que/active_job/extensions' if defined?(::ActiveJob)
