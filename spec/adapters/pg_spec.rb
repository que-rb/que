require 'spec_helper'

describe "Que using a bare PG connection" do
  before do
    Que.connection = QUE_CONNECTIONS[:pg]
  end

  it_behaves_like "a database connection"
end
