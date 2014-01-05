require 'spec_helper'
require 'connection_pool'

Que.connection = ConnectionPool.new &NEW_PG_CONNECTION
QUE_ADAPTERS[:connection_pool] = Que.adapter

describe "Que using the ConnectionPool adapter" do
  before { Que.adapter = QUE_ADAPTERS[:connection_pool] }

  it_behaves_like "a multi-threaded Que adapter"
end
