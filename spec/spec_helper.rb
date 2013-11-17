require 'que'

Dir["./spec/support/**/*.rb"].sort.each &method(:require)

QUE_URL = ENV["DATABASE_URL"] || "postgres://postgres:@localhost/que-test"

# Adapters track information about their connections like which statements
# have been prepared, and if Que.connection= is called before each spec, we're
# constantly creating new adapters and losing that information, which is bad.
# So instead, we hang onto a few adapters and assign them using Que.adapter=
# as needed. The plain pg adapter is the default.

# Also, let Que initialize the adapter itself, to make sure that the
# recognition logic works. Similar code can be found in the adapter specs.
require 'uri'
require 'pg'
uri = URI.parse(QUE_URL)
Que.connection = PG::Connection.open :host     => uri.host,
                                     :user     => uri.user,
                                     :password => uri.password,
                                     :port     => uri.port || 5432,
                                     :dbname   => uri.path[1..-1]
QUE_ADAPTERS = {:pg => Que.adapter}

# We use Sequel to introspect the database in specs.
require 'sequel'
DB = Sequel.connect(QUE_URL)
DB.drop_table? :que_jobs
DB.run Que::SQL[:create_table]

RSpec.configure do |config|
  config.before do
    DB[:que_jobs].delete
    $logger.messages.clear
    Que.adapter = QUE_ADAPTERS[:pg]
  end
end

# Set up a dummy logger.
Que.logger = $logger = Object.new
def $logger.messages; @messages ||= []; end
def $logger.method_missing(m, message); messages << message; end

# Helper for testing threaded code.
def sleep_until(timeout = 2)
  deadline = Time.now + timeout
  loop do
    break if yield
    raise "Thing never happened!" if Time.now > deadline
    sleep 0.01
  end
end
