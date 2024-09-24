# frozen_string_literal: true

# Silence Ruby warnings.
$VERBOSE = nil

require 'que'

# ActiveRecord and ActiveJob require ActiveSupport, which affects a bunch of
# core classes and may change some behavior that we rely on, so only bring it in
# in some spec runs.
if ENV['USE_RAILS'] == 'true'
  require 'active_record'
  require 'active_job'

  require 'que/active_job/extensions'

  ActiveJob::Base.queue_adapter = :que
  ActiveJob::Base.logger = nil
end

# Libraries necessary for tests.
require 'uri'
require 'pg'
require 'pry'
require 'pg_examiner'
require 'timeout'

# Connection pool sources.
require 'pond'
require 'connection_pool'

# Minitest stuff.
require 'minitest/autorun'
require 'minitest/pride'
require 'minitest/hooks'
require 'minitest/profile'

# "time travel" capabilities.
require 'timecop'
Timecop.safe_mode = true

# Other support stuff.
Dir['./spec/support/**/*.rb'].sort.each(&method(:require))



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

# Make it a bit easier to manage JSON when we're inspecting the DB in specs.
PARSE_JSON = -> (json) { JSON.parse(json, symbolize_names: true) }
DB.add_named_conversion_proc(:jsonb, &PARSE_JSON)
DB.add_named_conversion_proc(:json,  &PARSE_JSON)

# Have Que use a Sequel DB distinct from the one we use in our testing logic.
SEQUEL_TEST_DB = Sequel.connect(QUE_URL)



# Define connection pools of various types for testing purposes.

QUE_POOLS = {
  sequel:          SEQUEL_TEST_DB,
  pond:            Pond.new(&NEW_PG_CONNECTION),
  connection_pool: ConnectionPool.new(&NEW_PG_CONNECTION),
}.each_with_object({}) do |(name, source), hash|
  Que.connection = source
  hash[name] = Que.pool
end

if ENV['GITHUB_ACTIONS']
  puts "\n" + [
         "Ruby: #{RUBY_VERSION}",
         "PostgreSQL: #{DB["SHOW server_version"].get}",
         "Gemfile: #{ENV['BUNDLE_GEMFILE']}",
         "ActiveRecord: #{defined?(ActiveRecord) ? ActiveRecord.version.to_s : 'not loaded'}",
       ].join("\n")
end

# ActiveRecord requires ActiveSupport, which affects a bunch of core classes and
# may change some behavior that we rely on, so only bring it in sometimes.
if ENV['USE_RAILS'] == 'true'
  ActiveRecord::Base.establish_connection(QUE_URL)

  Que.connection = ActiveRecord
  QUE_POOLS[:active_record] = Que.pool

  # We won't have GlobalID if ActiveJob isn't defined.
  if defined?(::ActiveJob)
    class QueJob < ActiveRecord::Base
      include GlobalID::Identification
    end

    class TestLocator
      def locate(gid)
        gid.model_name.constantize.find(gid.model_id)
      end
    end

    GlobalID::Locator.use :test, TestLocator.new
    GlobalID.app = :test
  end
end

QUE_POOLS.freeze

Que.pool = DEFAULT_QUE_POOL = QUE_POOLS[:pond]



QUE_TABLES = [:que_jobs, :que_lockers, :que_values]

# Reset the schema to the most up-to-date version.
DB.drop_table?(*QUE_TABLES, cascade: true)
DB.drop_function :que_state_notify,  if_exists: true, cascade: true
DB.drop_function :que_validate_tags, if_exists: true, cascade: true, args: [:jsonb]
DB.drop_function :que_job_notify,    if_exists: true, cascade: true
Que::Migrations.migrate!(version: Que::Migrations::CURRENT_VERSION)



# Set up dummy loggers.
QUE_LOGGER          = DummyLogger.new
QUE_INTERNAL_LOGGER = DummyLogger.new

class QueSpec < Minitest::Spec
  include Minitest::Hooks

  SPEC_TIMEOUT        = (ENV['SPEC_TIMEOUT']       || (ENV['GITHUB_ACTIONS'] ? 10 : 600)).to_i
  TIME_SKEW           = (ENV['SPEC_TIME_SKEW']     || (ENV['GITHUB_ACTIONS'] ? 10 :   1)).to_i
  SLEEP_UNTIL_TIMEOUT = (ENV['SPEC_SLEEP_TIMEOUT'] || (ENV['GITHUB_ACTIONS'] ? 10 :   2)).to_i

  register_spec_type(//, self)

  let :locker_settings do
    {}
  end

  let :locker do
    Que::Locker.new(**locker_settings)
  end

  let :job_buffer do
    Que::JobBuffer.new(maximum_size: 20, priorities: [10, 30, 50, nil])
  end

  let :result_queue do
    Que::ResultQueue.new
  end

  let :worker do
    Que::Worker.new \
      job_buffer:   job_buffer,
      result_queue: result_queue
  end

  def results(message_type:)
    result_queue.to_a.select{|m| m[:message_type] == message_type}
  end

  def ids_in_local_queue
    locker.job_buffer.to_a.map(&:id)
  end

  # Sleep helpers for testing threaded code.
  def sleep_until_equal(expected, timeout: SLEEP_UNTIL_TIMEOUT)
    actual = nil
    sleep_until?(timeout: timeout) do
      actual = yield
      actual == expected
    end || raise("sleep_until_equal: expected #{expected.inspect}, got #{actual.inspect}")
  end

  def sleep_until(**args, &block)
    sleep_until?(**args, &block) || raise("sleep_until timeout reached")
  end

  def sleep_until?(timeout: SLEEP_UNTIL_TIMEOUT)
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

  def assert_raises_with_message(expected_error_class, expected_message, &block)
    e = assert_raises(expected_error_class, &block)
    assert_match(expected_message, e.message, "#{mu_pp(expected_error_class)} error was raised but without the expected message")
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

  def active_jobs_dataset
    jobs_dataset.where(finished_at: nil, expired_at: nil)
  end

  def expired_jobs_dataset
    jobs_dataset.exclude(expired_at: nil)
  end

  def finished_jobs_dataset
    jobs_dataset.exclude(finished_at: nil)
  end

  def listening_lockers
    DB[:que_lockers].where(:listening)
  end

  def logged_messages
    QUE_LOGGER.messages.map(&PARSE_JSON)
  end

  def internal_messages(event: nil)
    messages =
      QUE_INTERNAL_LOGGER.messages.map(&PARSE_JSON)

    messages.each do |message|
      assert_equal 'que',              message.delete(:lib)
      assert_equal Socket.gethostname, message.delete(:hostname)
      assert_equal Process.pid,        message.delete(:pid)
      assert_kind_of Integer,          message.delete(:thread)

      assert_in_delta Time.iso8601(message.delete(:t)), Time.now.utc, TIME_SKEW
    end

    if event
      messages = messages.select { |m| m[:internal_event] == event }
    end

    messages
  end

  def locked_ids
    DB[:pg_locks].where(locktype: 'advisory').select_order_map(Sequel.lit("(classid::bigint << 32) + objid::bigint"))
  end

  def current_spec_location
    location = self.class.instance_method(name).source_location.join(':')
    root_directory = File.expand_path('../..', __FILE__) << '/'
    spec_line = location.sub(root_directory, '')
    desc = self.class.to_s << '::' << name
    "#{desc} @ #{spec_line}"
  end

  def around
    puts "Running: #{current_spec_location}" if ENV['LOG_SPEC']

    # Don't let async error notifications hang around until the next spec.
    sleep_until { Que::Utils::ErrorNotification::ASYNC_QUEUE.empty? }
    sleep_until_equal("sleep") { Que.async_error_thread.status }

    Que.pool            = DEFAULT_QUE_POOL
    Que.logger          = QUE_LOGGER
    Que.internal_logger = QUE_INTERNAL_LOGGER
    Que.log_formatter   = nil

    Que.error_notifier = proc do |*args|
      puts
      puts "Error Notifier called: #{args.inspect}"
      puts current_spec_location
    end

    Que.job_middleware.clear
    Que.sql_middleware.clear

    Que.run_synchronously       = false
    Que.use_prepared_statements = true

    QUE_LOGGER.reset
    QUE_INTERNAL_LOGGER.reset

    $q1, $q2 = Queue.new, Queue.new
    $passed_args = nil

    begin
      # We want to make sure that none of our code assumes that job ids are in
      # the integer or bigint range. So, before every spec, reset the job id
      # sequence to a random value in one of those two ranges.
      max =
        if rand > 0.5
          2**63 - 1 # Postgres' maximum bigint.
        else
          2**31 - 1 # Postgres' maximum integer.
        end

      new_id = rand(max)

      DB.get{setval(Sequel.cast('que_jobs_id_seq', :regclass), new_id)}

      QUE_TABLES.each { |t| DB[t].delete }
    rescue Sequel::DatabaseError => e
      puts "\n\nPrevious spec left DB in unexpected state, run aborted\n\n"
      puts "\n\n#{e.class}: #{e.message}\n\n"
      abort
    end

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
    # Use the sleep because sometimes Postgres has a slight delay in cleaning
    # them up, but that shouldn't affect the (rare?) case where a bug leaves
    # them hanging.
    unless sleep_until? { locked_ids.empty? }
      puts "\n\nAdvisory lock left open: #{current_spec_location}\n\nLocks open: #{locked_ids.inspect}\n\n"
      # Again, no point in running the rest of the specs, since our state is
      # unknown/not clean.
      abort
    end
  end
end
