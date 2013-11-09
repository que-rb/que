require 'spec_helper'

describe "Que using ActiveRecord's connection" do
  before do
    Que.connection = QUE_CONNECTIONS[:active_record]
  end

  it_behaves_like "a database connection"
end
