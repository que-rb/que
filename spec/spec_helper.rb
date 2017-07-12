# frozen_string_literal: true

require 'que'
require 'uri'
require 'pg'
require 'logger'
require 'json'
require 'pond'
require 'pry'
require 'pg_examiner'
require 'timeout'

require 'minitest/autorun'
require 'minitest/pride'
require 'minitest/hooks'
require 'minitest/profile'

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



QUE_POND = Pond.new(collection: :stack, &NEW_PG_CONNECTION)
Que.connection_proc = QUE_POND.method(:checkout)
QUE_POOL = Que.pool



# We use Sequel to examine the database in specs.
require 'sequel'
DB = Sequel.connect(QUE_URL)
DB.extension :pg_array



if ENV['CI']
  puts "\n\n" + [
    "Ruby: #{RUBY_VERSION}",
    "PostgreSQL: #{DB["SHOW server_version"].get}",
    "Gemfile: #{ENV['BUNDLE_GEMFILE']}",
  ].join('; ')
end



# Reset the table to the most up-to-date version.
DB.drop_table? :que_jobs
DB.drop_table? :que_lockers
DB.drop_function :que_job_notify, if_exists: true
Que::Migrations.migrate!(version: Que::Migrations::CURRENT_VERSION)



# Set up a dummy logger.
Que.logger = QUE_LOGGER = Object.new
QUE_LOGGER_MUTEX = Mutex.new # Protect against rare errors on Rubinius/JRuby.

def QUE_LOGGER.messages
  @messages ||= []
end

def QUE_LOGGER.method_missing(m, message)
  QUE_LOGGER_MUTEX.synchronize { messages << message }
end

# Object includes Kernel#warn which is not what we expect, so remove:
def QUE_LOGGER.warn(message)
  method_missing(:warn, message)
end



class QueSpec < Minitest::Spec
  include Minitest::Hooks

  SPEC_TIMEOUT = (ENV['SPEC_TIMEOUT'] || (ENV['CI'] ? 1 : 600)).to_i

  register_spec_type(//, self)

  let :locker_settings do
    {
      poll_interval: nil,
    }
  end

  let :locker do
    Que::Locker.new(locker_settings)
  end

  def ids_in_local_queue
    locker.job_queue.to_a.map { |h| h.fetch(:id) }
  end

  # Travis seems to freeze the VM the tests run in sometimes, so bump up the
  # limit when running in CI.
  QUE_SLEEP_UNTIL_TIMEOUT = ENV['CI'] ? 10 : 2

  # Helper for testing threaded code.
  def sleep_until(timeout = QUE_SLEEP_UNTIL_TIMEOUT)
    deadline = Time.now + timeout
    loop do
      break if yield
      if Time.now > deadline
        puts "sleep_until timeout reached!"
        raise "sleep_until timeout reached!"
      end
      sleep 0.01
    end
  end

  def jobs_dataset
    DB[:que_jobs]
  end

  def logged_messages
    QUE_LOGGER.messages.map { |message| JSON.load(message) }
  end

  def locked_ids
    DB[:pg_locks].where(locktype: 'advisory').select_order_map(:objid)
  end

  def backend_pid(connection)
    connection.
      async_exec("select pg_backend_pid()").
      to_a.first['pg_backend_pid'].to_i
  end

  def current_spec_location
    location = self.class.instance_method(name).source_location.join(':')
    root_directory = File.expand_path('../..', __FILE__) << '/'
    spec_line = location.sub(root_directory, '')
    desc = self.class.to_s << '::' << name
    "#{desc} @ #{spec_line}"
  end

  def around
    Que.pool = QUE_POOL

    QUE_LOGGER.messages.clear
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
      # We're now in an unknown state, so there's no point in running the rest
      # of the specs - they'll just add a bunch of obfuscating output.
      abort
    end

    # A bit of lint: make sure that no specs leave advisory locks hanging open.
    unless locked_ids.empty?
      puts "\n\nAdvisory lock left open: #{current_spec_location}\n\n"
      # Again, no point in running the rest of the specs, since our state is
      # unknown/not clean.
      abort
    end

    DB[:que_jobs].delete
    DB[:que_lockers].delete
  end
end
