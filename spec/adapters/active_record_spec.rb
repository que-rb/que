require 'spec_helper'

require 'active_record'

describe "Que using ActiveRecord's connection" do
  before :all do
    ActiveRecord::Base.establish_connection(QUE_URL)
    Que.connection = ActiveRecord
  end

  it_behaves_like "a Que backend"
end
