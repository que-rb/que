require 'spec_helper'

require 'sequel'

describe "Que using a Sequel database's connection" do
  before :all do
    Que.connection = Sequel.connect(QUE_URL)
  end

  it_behaves_like "a Que backend"
end
