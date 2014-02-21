require 'socket' # For Socket.gethostname

module Que
  autoload :Adapter,     'que/adapter'
  autoload :Job,         'que/job'
  autoload :JobQueue,    'que/job_queue'
  autoload :Locker,      'que/locker'
  autoload :Migrations,  'que/migrations'
  autoload :ResultQueue, 'que/result_queue'
  autoload :SQL,         'que/sql'
  autoload :Version,     'que/version'
  autoload :Worker,      'que/worker'

  begin
    require 'multi_json'
    JSON_MODULE = MultiJson
  rescue LoadError
    require 'json'
    JSON_MODULE = JSON
  end

  class << self
    attr_accessor :logger, :error_handler, :mode
    attr_writer :adapter, :log_formatter

    def connection=(connection)
      self.adapter = connection && Adapter.new(connection)
    end

    def adapter
      @adapter || raise("Que connection not established!")
    end

    def execute(*args)
      adapter.execute(*args)
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

    # Give us a cleaner interface when specifying a job_class as a string.
    def enqueue(*args)
      Job.enqueue(*args)
    end

    def db_version
      Migrations.db_version
    end

    def migrate!(version = {:version => Migrations::CURRENT_VERSION})
      Migrations.migrate!(version)
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
  end
end

require 'que/railtie' if defined? Rails::Railtie
