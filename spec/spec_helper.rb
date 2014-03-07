require 'que'
require 'uri'
require 'pg'
require 'logger'
require 'json'
require 'pond'

Dir['./spec/support/**/*.rb'].sort.each &method(:require)



# Handy constants for initializing PG connections:
QUE_URL = ENV['DATABASE_URL'] || 'postgres://postgres:@localhost/que-test'

NEW_PG_CONNECTION = proc do
  uri = URI.parse(QUE_URL)
  pg = PG::Connection.open :host     => uri.host,
                           :user     => uri.user,
                           :password => uri.password,
                           :port     => uri.port || 5432,
                           :dbname   => uri.path[1..-1]

  # Avoid annoying NOTICE messages in specs.
  pg.async_exec "SET client_min_messages TO 'warning'"
  pg
end



# Connection pools are wrapped by Que::Pool instances, which are responsible
# for tracking which statements have been prepared for their connections, and
# if Que.connection_proc= is called before each spec, we're constantly
# creating new pools and losing that information, which is bad. So instead, we
# hang onto a few pools and assign them using Que.pool= as needed. The Pond
# pool is the default. Since the specs were originally designed for a stack-
# based pool (the connection_pool gem), use :stack mode to avoid issues.

QUE_SPEC_POND = Pond.new :collection => :stack, &NEW_PG_CONNECTION
Que.connection_proc = QUE_SPEC_POND.method(:checkout)
QUE_POOLS = {:pond => Que.pool}



# We use Sequel to examine the database in specs.
require 'sequel'
DB = Sequel.connect(QUE_URL)



# Reset the table to the most up-to-date version.
DB.drop_table? :que_jobs
DB.drop_table? :que_lockers
DB.drop_function :que_job_notify, :if_exists => true
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



# Helper to display spec descriptions.
description_builder = -> hash do
  if g = hash[:example_group]
    "#{description_builder.call(g)} #{hash[:description_args].first}"
  else
    hash[:description_args].first
  end
end

stdout = Logger.new(STDOUT)

RSpec.configure do |config|
  config.around do |spec|
    # Figure out which spec is about to run, for logging purposes.
    data = example.metadata
    desc = description_builder.call(data)
    line = "rspec #{data[:file_path]}:#{data[:line_number]}"

    # Optionally log to STDOUT which spec is about to run. This is noisy, but
    # helpful in identifying hanging specs.
    stdout.info "Running spec: #{desc} @ #{line}" if ENV['LOG_SPEC']

    Que.pool = QUE_POOLS[:pond]
    Que.mode = :off
    $logger.messages.clear

    spec.run

    DB[:que_jobs].delete
    DB[:que_lockers].delete

    # A bit of lint: make sure that no advisory locks are left open.
    unless DB[:pg_locks].where(:locktype => 'advisory').empty?
      stdout.info "Advisory lock left open: #{desc} @ #{line}"
    end
  end
end
