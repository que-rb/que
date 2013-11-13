require 'que'

Dir["./spec/support/**/*.rb"].sort.each &method(:require)

require 'uri'
url = ENV["DATABASE_URL"] || "postgres://postgres:@localhost/que-test"
uri = URI.parse(url)

require 'pg'
require 'sequel'
require 'active_record'

ActiveRecord::Base.establish_connection(url)

QUE_CONNECTIONS = {
  :active_record => ActiveRecord,
  :sequel        => Sequel.connect(url),
  :pg            => PG::Connection.open(
                      :host     => uri.host,
                      :user     => uri.user,
                      :password => uri.password,
                      :port     => uri.port || 5432,
                      :dbname   => uri.path[1..-1]
                    )
}

# There are two Sequel database instances - one in the QUE_CONNECTIONS hash
# that's used to test Que's Sequel integration, and one in the DB constant
# that's used to in the specs to introspect/manipulate the database directly.
DB = Sequel.connect(url)
DB.drop_table? :que_jobs
DB.run Que::SQL.create_sql

RSpec.configure do |config|
  config.before do
    DB[:que_jobs].delete
  end
end
