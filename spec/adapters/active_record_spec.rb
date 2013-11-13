require 'spec_helper'

require 'active_record'

ActiveRecord::Base.establish_connection(QUE_URL)

describe "Que using ActiveRecord's connection" do
  before do
    Que.connection = ActiveRecord
  end

  it_behaves_like "a Que backend"
end
