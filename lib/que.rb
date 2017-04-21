# frozen_string_literal: true

require 'forwardable'
require 'socket' # For Socket.gethostname
require 'json'

module Que
  class Error < StandardError; end

  CURRENT_HOSTNAME = Socket.gethostname.freeze
  DEFAULT_QUEUE = ''.freeze

  require_relative 'que/config'
  require_relative 'que/connection_pool'
  require_relative 'que/job'
  require_relative 'que/job_queue'
  require_relative 'que/locker'
  require_relative 'que/migrations'
  require_relative 'que/result_queue'
  require_relative 'que/sql'
  require_relative 'que/version'
  require_relative 'que/worker'

  class << self
    extend Forwardable

    # Copy some commonly-used methods here, for convenience.
    def_delegators :pool, :execute, :checkout, :in_transaction?
    def_delegators Job, :enqueue
    def_delegators Migrations, :db_version, :migrate!

    def clear!
      execute "DELETE FROM que_jobs"
    end

    def job_stats
      execute :job_stats
    end

    def job_states
      execute :job_states
    end

    # Have to support create! and drop! for old migrations. They just created
    # and dropped the bare table.
    def create!
      migrate! version: 1
    end

    def drop!
      migrate! version: 0
    end

    def log(level: :info, **data)
      data =
        {
          lib:      :que,
          hostname: CURRENT_HOSTNAME,
          pid:      Process.pid,
          thread:   Thread.current.object_id
        }.merge(data)

      if l = logger
        begin
          if output = log_formatter.call(data)
            l.send level, output
          end
        rescue => e
          msg =
            "Error raised from Que.log_formatter proc:" +
            " #{e.class}: #{e.message}\n#{e.backtrace}"

          l.error(msg)
        end
      end
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
  end
end
