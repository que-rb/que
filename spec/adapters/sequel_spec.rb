require 'spec_helper'

describe "Que using a Sequel database's connection" do
  before do
    Que.connection = QUE_CONNECTIONS[:sequel]
  end

  it_behaves_like "a database connection"
end
