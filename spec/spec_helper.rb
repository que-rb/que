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
