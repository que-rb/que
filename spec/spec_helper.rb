# frozen_string_literal: true

require 'que'
require 'uri'
require 'pg'
require 'logger'
require 'json'
require 'pond'
require 'pry'

require 'minitest/autorun'
require 'minitest/pride'

Dir['./spec/support/**/*.rb'].sort.each &method(:require)



# Handy constants for initializing PG connections:
QUE_URL = ENV['DATABASE_URL'] || 'postgres://postgres:@localhost/que-test'

NEW_PG_CONNECTION = proc do
  uri = URI.parse(QUE_URL)
  pg = PG::Connection.open host:     uri.host,
                           user:     uri.user,
                           password: uri.password,
                           port:     uri.port || 5432,
                           dbname:   uri.path[1..-1]

  # Avoid annoying NOTICE messages in specs.
  pg.async_exec "SET client_min_messages TO 'warning'"
  pg
end



QUE_POND = Pond.new(collection: :stack, &NEW_PG_CONNECTION)
Que.connection_proc = QUE_POND.method(:checkout)
QUE_POOL = Que.pool



# We use Sequel to examine the database in specs.
require 'sequel'
DB = Sequel.connect(QUE_URL)



if ENV['CI']
  DB.synchronize do |conn|
    puts "Ruby #{RUBY_VERSION}"
    puts "Sequel #{Sequel::VERSION}"
    puts conn.async_exec("SELECT version()").to_a.first['version']
  end
end



# Reset the table to the most up-to-date version.
DB.drop_table? :que_jobs
DB.drop_table? :que_lockers
DB.drop_function :que_job_notify, if_exists: true
Que::Migrations.migrate!



# Set up a dummy logger.
Que.logger = $logger = Object.new
$logger_mutex = Mutex.new # Protect against rare errors on Rubinius/JRuby.

def $logger.messages
  @messages ||= []
end

def $logger.method_missing(m, message)
  $logger_mutex.synchronize { messages << message }
end

# Object includes Kernel#warn which is not what we expect, so remove:
def $logger.warn(message)
  method_missing(:warn, message)
end



SPEC_LOGGER = Logger.new(STDOUT)

class QueSpec < Minitest::Spec
  register_spec_type(//, self)

  def setup
    # # Figure out which spec is about to run, for logging purposes.
    # data = spec.metadata
    # desc = data[:full_description]
    # line = "rspec #{data[:file_path]}:#{data[:line_number]}"

    # # Optionally log to STDOUT which spec is about to run. This is noisy, but
    # # helpful in identifying hanging specs.
    # SPEC_LOGGER.info "Running spec: #{desc} @ #{line}" if ENV['LOG_SPEC']

    Que.pool = QUE_POOL
    # Que.mode = :async

    $logger.messages.clear
    $q1, $q2 = Queue.new, Queue.new
    $passed_args = nil

    DB[:que_jobs].delete
    DB[:que_lockers].delete
  end

  def teardown
    Que.mode = :off

    DB[:que_jobs].delete
    DB[:que_lockers].delete

    # A bit of lint: make sure that no advisory locks are left open.
    unless DB[:pg_locks].where(locktype: 'advisory').empty?
      SPEC_LOGGER.info "Advisory lock left open: #{desc} @ #{line}"
    end
  end
end
