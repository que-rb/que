require 'spec_helper'
require 'pond'

Que.connection = QUE_SPEC_POND = Pond.new &NEW_PG_CONNECTION
QUE_ADAPTERS[:pond] = Que.adapter

describe "Que using the Pond adapter" do
  before { Que.adapter = QUE_ADAPTERS[:pond] }

  it_behaves_like "a multi-threaded Que adapter"

  it "should be able to tell when it's already in a transaction" do
    Que.adapter.should_not be_in_transaction
    QUE_SPEC_POND.checkout do |conn|
      conn.async_exec "BEGIN"
      Que.adapter.should be_in_transaction
      conn.async_exec "COMMIT"
    end
  end
end
