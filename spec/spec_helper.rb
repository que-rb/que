require 'que'
require 'uri'

Dir["./spec/support/**/*.rb"].sort.each &method(:require)


QUE_URL      = ENV["DATABASE_URL"] || "postgres://postgres:@localhost/que-test"
QUE_ADAPTERS = {}

if jruby?
  # TODO
else
  # Handy proc to instantiate new PG connections:
  require 'pg'
  NEW_PG_CONNECTION = proc do
    uri = URI.parse(QUE_URL)
    PG::Connection.open :host     => uri.host,
                        :user     => uri.user,
                        :password => uri.password,
                        :port     => uri.port || 5432,
                        :dbname   => uri.path[1..-1]
  end



  # Adapters track information about their connections like which statements
  # have been prepared, and if Que.connection= is called before each spec, we're
  # constantly creating new adapters and losing that information, which is bad.
  # So instead, we hang onto a few adapters and assign them using Que.adapter=
  # as needed. The plain pg adapter is the default.

  # Also, let Que initialize the adapter itself, to make sure that the
  # recognition logic works. Similar code can be found in the adapter specs.
  Que.connection = NEW_PG_CONNECTION.call
  QUE_ADAPTERS[:default] = Que.adapter
end



# We use Sequel to introspect the database in specs.
require 'sequel'
DB = Sequel.connect(jruby? ? convert_url_to_jdbc(QUE_URL) : QUE_URL)
DB.drop_table? :que_jobs
DB.run Que::SQL[:create_table]

RSpec.configure do |config|
  config.before do
    DB[:que_jobs].delete
    Que.adapter = QUE_ADAPTERS[:default]
    Que.mode = :off
    Que.sleep_period = nil
    $logger.messages.clear
  end
end



# Set up a dummy logger.
Que.logger = $logger = Object.new
def $logger.messages;                   @messages ||= [];    end
def $logger.method_missing(m, message); messages << message; end
