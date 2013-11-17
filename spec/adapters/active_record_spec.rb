require 'spec_helper'
require 'active_record'

ActiveRecord::Base.establish_connection(QUE_URL)
Que.connection = ActiveRecord
QUE_ADAPTERS[:active_record] = Que.adapter

describe "Que using ActiveRecord's connection" do
  before { Que.adapter = QUE_ADAPTERS[:active_record] }

  it_behaves_like "a Que backend"
end
