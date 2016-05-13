# frozen_string_literal: true

require 'spec_helper'
require 'connection_pool'

Que.connection = QUE_SPEC_CONNECTION_POOL = ConnectionPool.new &NEW_PG_CONNECTION
QUE_POOLS[:connection_pool] = Que.pool

describe "Que using ConnectionPool" do
  before { Que.pool = QUE_POOLS[:connection_pool] }

  it_behaves_like "a Que pool"

  it "should be able to tell when it's already in a transaction" do
    Que.should_not be_in_transaction
    QUE_SPEC_CONNECTION_POOL.with do |conn|
      conn.async_exec "BEGIN"
      Que.should be_in_transaction
      conn.async_exec "COMMIT"
    end
  end
end
