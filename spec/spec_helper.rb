require 'que'
require 'uri'
require 'pg'
require 'json'

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


# Clean up between specs.
RSpec.configure do |config|
  config.before do
    DB[:que_jobs].delete
    Que.adapter = QUE_ADAPTERS[:pg]
    Que.mode = :off
    Que.sleep_period = nil
    $logger.messages.clear
  end

  config.after do
    # A bit of lint: make sure that after each spec, no advisory locks are left open.
    DB[:pg_locks].where(:locktype => 'advisory').should be_empty
  end
end


# Optionally log to STDOUT which spec is running at the moment. This is loud,
# but helpful in tracking down what spec is hanging, if any.
if ENV['LOG_SPEC']
  require 'logger'
  logger = Logger.new(STDOUT)

  description_builder = -> hash do
    if g = hash[:example_group]
      "#{description_builder.call(g)} #{hash[:description_args].first}"
    else
      hash[:description_args].first
    end
  end

  RSpec.configure do |config|
    config.around do |example|
      data = example.metadata
      desc = description_builder.call(data)
      line = "rspec #{data[:file_path]}:#{data[:line_number]}"
      logger.info "Running spec: #{desc} @ #{line}"

      example.run
    end
  end
end
