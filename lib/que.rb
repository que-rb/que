# frozen_string_literal: true

require 'forwardable'
require 'socket' # For Socket.gethostname

module Que
  CURRENT_HOSTNAME = Socket.gethostname.freeze
  DEFAULT_QUEUE    = 'default'.freeze
  TIME_REGEX       = /\A\d{4}\-\d{2}\-\d{2}T\d{2}:\d{2}:\d{2}.\d{6}Z\z/
  CONFIG_MUTEX     = Mutex.new

  class Error < StandardError; end

  # Need support for object registration early.
  require_relative 'que/utils/registrar'

  # Store SQL strings frozen, with squashed whitespace so logs read better.
  SQL = Utils::Registrar.new { |sql| sql.strip.gsub(/\s+/, ' ').freeze }

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
  require_relative 'que/utils/queue_management'
  require_relative 'que/utils/transactions'

  require_relative 'que/connection'
  require_relative 'que/connection_pool'
  require_relative 'que/job'
  require_relative 'que/job_queue'
  require_relative 'que/locker'
  require_relative 'que/migrations'
  require_relative 'que/poller'
  require_relative 'que/result_queue'
  require_relative 'que/version'
  require_relative 'que/worker'

  class << self
    include Utils::Assertions
    include Utils::Constantization
    include Utils::ErrorNotification
    include Utils::Freeze
    include Utils::Introspection
    include Utils::JSONSerialization
    include Utils::Logging
    include Utils::QueueManagement
    include Utils::Transactions

    extend Forwardable

    # Copy some commonly-used methods here, for convenience.
    def_delegators :pool, :execute, :checkout, :in_transaction?
    def_delegators Job, :enqueue, :run_synchronously, :run_synchronously=
    def_delegators Migrations, :db_version, :migrate!

    # Global configuration logic.
    attr_writer :default_queue

    def default_queue
      @default_queue || DEFAULT_QUEUE
    end

    ACTIVE_RECORD_PROC = proc do |&block|
      ActiveRecord::Base.connection_pool.with_connection do |c|
        block.call(c.raw_connection)
      end
    end

    def connection=(connection)
      self.connection_proc =
        if connection.to_s == 'ActiveRecord'
          ACTIVE_RECORD_PROC
        else
          case connection.class.to_s
          when 'Sequel::Postgres::Database'
            connection.method(:synchronize)
          when 'Pond', 'ConnectionPool'
            connection.method(:checkout)
          when 'NilClass'
            connection
          else
            raise Error, "Unsupported connection: #{connection.class}"
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
end
