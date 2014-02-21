require 'spec_helper'
require 'connection_pool'

QUE_SPEC_CONNECTION_POOL = ConnectionPool.new &NEW_PG_CONNECTION
Que.connection = QUE_SPEC_CONNECTION_POOL.method(:with)
QUE_ADAPTERS[:connection_pool] = Que.adapter

describe "Que using the ConnectionPool adapter" do
  before { Que.adapter = QUE_ADAPTERS[:connection_pool] }

  it_behaves_like "a Que adapter"

  it "should be able to tell when it's already in a transaction" do
    Que.adapter.should_not be_in_transaction
    QUE_SPEC_CONNECTION_POOL.with do |conn|
      conn.async_exec "BEGIN"
      Que.adapter.should be_in_transaction
      conn.async_exec "COMMIT"
    end
  end
end
