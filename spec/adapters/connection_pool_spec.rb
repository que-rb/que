require 'spec_helper'

require 'uri'
require 'pg'
require 'connection_pool'

uri  = URI.parse(QUE_URL)
pool = ConnectionPool.new :size => 2 do
  PG::Connection.open :host     => uri.host,
                      :user     => uri.user,
                      :password => uri.password,
                      :port     => uri.port || 5432,
                      :dbname   => uri.path[1..-1]
end

describe "Que using a PG connection wrapped in a connection pool" do
  before do
    Que.connection = pool
  end

  it_behaves_like "a Que backend"
end
