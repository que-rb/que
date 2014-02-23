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
  require_relative 'que/locker'
  require_relative 'que/migrations'
  require_relative 'que/pool'
  require_relative 'que/priority_queue'
  require_relative 'que/sql'
  require_relative 'que/version'
  require_relative 'que/worker'

  class << self
    extend Forwardable

    attr_accessor :logger, :error_handler, :mode
    attr_writer :pool, :log_formatter

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
      data = {:lib => 'que', :hostname => Socket.gethostname, :thread => Thread.current.object_id}.merge(data)

      if logger && output = log_formatter.call(data)
        logger.send level, output
      end
    end

    def log_formatter
      @log_formatter ||= JSON_MODULE.method(:dump)
    end

    # Make hashes indifferently-accessible.
    def indifferentiate(object)
      case object
      when Hash
        if object.respond_to?(:with_indifferent_access)
          object.with_indifferent_access
        else
          object.default_proc = HASH_DEFAULT_PROC
          object.each { |key, value| object[key] = indifferentiate(value) }
        end
      when Array
        object.map! { |element| indifferentiate(element) }
      else
        object
      end
    end

    HASH_DEFAULT_PROC = proc { |hash, key| hash[key.to_s] if Symbol === key }

    # Copy some commonly-used methods here, for convenience.
    def_delegators :pool, :execute, :checkout, :in_transaction?
    def_delegators Job, :enqueue
    def_delegators Migrations, :db_version, :migrate!
  end
end

require 'que/railtie' if defined? Rails::Railtie
