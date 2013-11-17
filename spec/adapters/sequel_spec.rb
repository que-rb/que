require 'spec_helper'

Que.connection = Sequel.connect(QUE_URL)
QUE_ADAPTERS[:sequel] = Que.adapter

describe "Que using a Sequel database's connection" do
  before { Que.adapter = QUE_ADAPTERS[:sequel] }

  it_behaves_like "a Que adapter"
  it_behaves_like "a multithreaded Que adapter"
end
