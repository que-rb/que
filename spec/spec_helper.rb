# frozen_string_literal: true

require 'que'

# Libraries necessary for tests.
require 'uri'
require 'pg'
require 'pry'
require 'pg_examiner'
require 'timeout'

# Connection pool sources.
require 'pond'
require 'connection_pool'

# ActiveRecord and ActiveJob require ActiveSupport, which affects a bunch of
# core classes and may change some behavior that we rely on, so only bring it in
# in some spec runs.
if ENV['USE_RAILS'] == 'true'
  require 'active_record'

  begin
    require 'active_job'

    ActiveJob::Base.queue_adapter = :que
    ActiveJob::Base.logger = nil

    require 'que/rails/active_job'
  rescue LoadError
    # We're on an old Gemfile where ActiveJob isn't available - no biggie.
  end
end

# Minitest stuff.
require 'minitest/autorun'
require 'minitest/pride'
require 'minitest/hooks'
require 'minitest/profile'

# Other support stuff.
Dir['./spec/support/**/*.rb'].sort.each &method(:require)



# Handy constants for initializing PG connections:
QUE_URL = ENV['DATABASE_URL'] || 'postgres://postgres:@localhost/que-test'

NEW_PG_CONNECTION = proc do
  uri = URI.parse(QUE_URL)
  pg =
    PG::Connection.open(
      host:     uri.host,
      user:     uri.user,
      password: uri.password,
      port:     uri.port || 5432,
      dbname:   uri.path[1..-1],
    )

  # Avoid annoying NOTICE messages in specs.
  pg.async_exec "SET client_min_messages TO 'warning'"
  pg
end

EXTRA_PG_CONNECTION = NEW_PG_CONNECTION.call



# We use Sequel to examine the database in specs.
require 'sequel'
DB = Sequel.connect(QUE_URL)
DB.extension :pg_array
DB.extension :pg_json

def Sequel.parse_json(json)
  JSON.parse(json, symbolize_names: true, create_additions: false)
end



# Define connection pools of various types for testing purposes.

QUE_POOLS = {
  sequel:          DB,
  pond:            Pond.new(&NEW_PG_CONNECTION),
  connection_pool: ConnectionPool.new(&NEW_PG_CONNECTION),
}.
each_with_object({}) do |(name, source), hash|
  Que.connection = source
  hash[name] = Que.pool
end

# ActiveRecord requires ActiveSupport, which affects a bunch of core classes and
# may change some behavior that we rely on, so only bring it in sometimes.
if ENV['USE_RAILS'] == 'true'
  ActiveRecord::Base.establish_connection(QUE_URL)

  Que.connection = ActiveRecord
  QUE_POOLS[:active_record] = Que.pool
end

QUE_POOLS.freeze

Que.pool = DEFAULT_QUE_POOL = QUE_POOLS[:pond]



if ENV['CI']
  puts "\n\n" + [
    "Ruby: #{RUBY_VERSION}",
    "PostgreSQL: #{DB["SHOW server_version"].get}",
    "Gemfile: #{ENV['BUNDLE_GEMFILE']}",
    "ActiveRecord: #{defined?(ActiveRecord) ? ActiveRecord.version.to_s : 'not loaded'}",
  ].join("\n")
end



# Reset the table to the most up-to-date version.
DB.drop_table? :que_jobs
DB.drop_table? :que_lockers
DB.drop_function :que_job_notify, if_exists: true
Que::Migrations.migrate!(version: Que::Migrations::CURRENT_VERSION)



# Set up dummy loggers.
QUE_LOGGER          = DummyLogger.new
QUE_INTERNAL_LOGGER = DummyLogger.new

class QueSpec < Minitest::Spec
  include Minitest::Hooks

  SPEC_TIMEOUT = (ENV['SPEC_TIMEOUT'] || (ENV['CI'] ? 10 : 600)).to_i
  SLEEP_UNTIL_TIMEOUT = 2

  register_spec_type(//, self)

  let :locker_settings do
    {}
  end

  let :locker do
    Que::Locker.new(locker_settings)
  end

  def ids_in_local_queue
    locker.job_queue.to_a.map { |h| h.fetch(:id) }
  end

  # Helper for testing threaded code.
  def sleep_until!(*args, &block)
    sleep_until(*args, &block) || raise("sleep_until! timeout reached")
  end

  def sleep_until(timeout = SLEEP_UNTIL_TIMEOUT)
    deadline = Time.now + timeout
    loop do
      if result = yield
        return result
      end

      if Time.now > deadline
        return false
      end

      sleep 0.01
    end
  end

  class << self
    # More easily hammer a certain spec.
    def hit(*args, &block)
      100.times { it(*args, &block) }
    end
  end

  def jobs_dataset
    DB[:que_jobs]
  end

  def listening_lockers
    DB[:que_lockers].where(:listening)
  end

  def logged_messages
    QUE_LOGGER.messages.map { |message| JSON.parse(message, symbolize_names: true) }
  end

  def internal_messages(event: nil)
    messages =
      QUE_INTERNAL_LOGGER.messages.map { |m| JSON.parse(m, symbolize_names: true) }

    messages.each do |message|
      assert_equal 'que',              message.delete(:lib)
      assert_equal Socket.gethostname, message.delete(:hostname)
      assert_equal Process.pid,        message.delete(:pid)
      assert_kind_of Integer,          message.delete(:thread)

      assert_in_delta Time.iso8601(message.delete(:t)), Time.now.utc, 5
    end

    if event
      messages = messages.select { |m| m[:internal_event] == event }
    end

    messages
  end

  def locked_ids
    DB[:pg_locks].where(locktype: 'advisory').select_order_map(:objid)
  end

  def current_spec_location
    location = self.class.instance_method(name).source_location.join(':')
    root_directory = File.expand_path('../..', __FILE__) << '/'
    spec_line = location.sub(root_directory, '')
    desc = self.class.to_s << '::' << name
    "#{desc} @ #{spec_line}"
  end

  DEFAULT_ERROR_NOTIFIER = proc do |*args|
    puts "Error Notifier called: #{args.inspect}"
  end

  def around
    puts "Running: #{current_spec_location}" if ENV['LOG_SPEC']

    Que.pool            = DEFAULT_QUE_POOL
    Que.logger          = QUE_LOGGER
    Que.internal_logger = QUE_INTERNAL_LOGGER
    Que.log_formatter   = nil
    Que.error_notifier  = DEFAULT_ERROR_NOTIFIER
    Que.middleware.clear

    QUE_LOGGER.messages.clear
    QUE_INTERNAL_LOGGER.messages.clear

    $q1, $q2 = Queue.new, Queue.new
    $passed_args = nil

    DB[:que_jobs].delete
    DB[:que_lockers].delete

    # Timeout is a problematic module in general, since it leaves things in an
    # unknown and unsafe state. It should be avoided in library code, but in
    # specs to ensure that they don't hang forever, it should be fine.
    begin
      Timeout.timeout(SPEC_TIMEOUT) { super }
    rescue Timeout::Error => e
      puts "\n\nSpec timed out: #{current_spec_location}\n\n"
      puts "Timed out at:\n\n#{e.backtrace.join("\n")}\n\n"
      # We're now in an unknown state, so there's no point in running the rest
      # of the specs - they'll just add a bunch of obfuscating output.
      abort
    end

    if (f = failure) && !skipped?
      begin
        e = f.exception
        puts "\n\n#{e.class}: #{e.message}\n#{e.backtrace.join("\n")}\n\n"
      rescue => error
        puts "#{error.class}: #{error.message}"
      end
    end

    # A bit of lint: make sure that no specs leave advisory locks hanging open.
    unless locked_ids.empty?
      puts "\n\nAdvisory lock left open: #{current_spec_location}\n\n"
      # Again, no point in running the rest of the specs, since our state is
      # unknown/not clean.
      abort
    end
  end
end
