require 'que'

Dir["./spec/support/**/*.rb"].sort.each &method(:require)

QUE_URL = ENV["DATABASE_URL"] || "postgres://postgres:@localhost/que-test"

# We use Sequel to introspect the database in specs.
require 'sequel'

DB = Sequel.connect(QUE_URL)
DB.drop_table? :que_jobs
DB.run Que::SQL[:create_table]

RSpec.configure do |config|
  config.before do
    DB[:que_jobs].delete
    $logger.messages.clear
  end
end

# Set up a dummy logger.
$logger = Object.new

def $logger.messages
  @messages ||= []
end

def $logger.method_missing(m, message)
  messages << message
end

Que.logger = $logger

# Helper for testing threaded code.
def sleep_until(timeout = 2)
  deadline = Time.now + timeout
  loop do
    break if yield
    raise "Thing never happened!" if Time.now > deadline
    sleep 0.01
  end
end
