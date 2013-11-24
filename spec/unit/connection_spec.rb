require 'spec_helper'

describe Que do
  it ".adapter when no connection has been established should raise an error" do
    Que.connection = nil
    proc{Que.adapter}.should raise_error RuntimeError, /Que connection not established!/
  end
end
