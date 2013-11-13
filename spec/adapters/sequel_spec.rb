require 'spec_helper'

require 'sequel'

sequel = Sequel.connect(QUE_URL)

describe "Que using a Sequel database's connection" do
  before do
    Que.connection = sequel
  end

  it_behaves_like "a Que backend"
end
