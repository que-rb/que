require 'spec_helper'
require 'connection_pool'

uri = URI.parse(QUE_URL)
Que.connection = ConnectionPool.new :size => 2, &NEW_PG_CONNECTION
QUE_ADAPTERS[:connection_pool] = Que.adapter

describe "Que using a PG connection wrapped in a connection pool" do
  before { Que.adapter = QUE_ADAPTERS[:connection_pool] }

  it_behaves_like "a Que adapter"
  it_behaves_like "a multithreaded Que adapter"
end
