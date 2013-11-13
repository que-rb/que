require 'spec_helper'

require 'uri'
require 'pg'

uri = URI.parse(QUE_URL)
pg  = PG::Connection.open :host     => uri.host,
                          :user     => uri.user,
                          :password => uri.password,
                          :port     => uri.port || 5432,
                          :dbname   => uri.path[1..-1]

describe "Que using a bare PG connection" do
  before do
    Que.connection = pg
  end

  it_behaves_like "a Que backend"
end
