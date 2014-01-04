require 'que'
require 'uri'
require 'pg'
require 'json'
require 'logger'

stdout = Logger.new(STDOUT)
Dir['./spec/support/**/*.rb'].sort.each &method(:require)


# Handy constants for initializing PG connections:
QUE_URL = ENV['DATABASE_URL'] || 'postgres://postgres:@localhost/que-test'

NEW_PG_CONNECTION = proc do
  uri = URI.parse(QUE_URL)
  PG::Connection.open :host     => uri.host,
                      :user     => uri.user,
                      :password => uri.password,
                      :port     => uri.port || 5432,
                      :dbname   => uri.path[1..-1]
end


# Adapters track which statements have been prepared for their connections,
# and if Que.connection= is called before each spec, we're constantly creating
# new adapters and losing that information, which is bad. So instead, we hang
# onto a few adapters and assign them using Que.adapter= as needed. The plain
# pg adapter is the default.

# Also, let Que initialize the adapter itself, to make sure that the
# recognition logic works. Similar code can be found in the adapter specs.
Que.connection = NEW_PG_CONNECTION.call
QUE_ADAPTERS = {:pg => Que.adapter}


# We use Sequel to introspect the database in specs.
require 'sequel'
DB = Sequel.connect(QUE_URL)
DB.drop_table? :que_jobs
DB.run Que::SQL[:create_table]


# Set up a dummy logger.
Que.logger = $logger = Object.new

def $logger.messages
  @messages ||= []
end

def $logger.method_missing(m, message)
  messages << message
end


# Callbacks for specs.
reset = -> do
  Que.sleep_period = nil
  Que.mode = :off
  DB[:que_jobs].delete
  Que.adapter = QUE_ADAPTERS[:pg]
  sleep_until { Que::Worker.workers.all?(&:sleeping?) }
  $logger.messages.clear
end

# Helper to display spec descriptions.
description_builder = -> hash do
  if g = hash[:example_group]
    "#{description_builder.call(g)} #{hash[:description_args].first}"
  else
    hash[:description_args].first
  end
end

RSpec.configure do |config|
  config.around do |spec|
    # Figure out which spec is about to run, for logging purposes.
    data = example.metadata
    desc = description_builder.call(data)
    line = "rspec #{data[:file_path]}:#{data[:line_number]}"

    # Optionally log to STDOUT which spec is about to run. This is noisy, but
    # helpful in identifying hanging specs.
    stdout.info "Running spec: #{desc} @ #{line}" if ENV['LOG_SPEC']

    spec.run

    reset.call

    # A bit of lint: make sure that no advisory locks are left open.
    unless DB[:pg_locks].where(:locktype => 'advisory').empty?
      stdout.info "Advisory lock left open: #{desc} @ #{line}"
    end
  end
end

# Clean up before any specs run.
reset.call
