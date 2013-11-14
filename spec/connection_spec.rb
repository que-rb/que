require 'spec_helper'

describe Que do
  it ".connection= with an unsupported connection should raise an error" do
    proc{Que.connection = "ferret"}.should raise_error RuntimeError, /Que connection not recognized: "ferret"/
  end

  it ".connection when no connection has been established should raise an error" do
    Que.connection = nil
    proc{Que.connection}.should raise_error RuntimeError, /Que connection not established!/
  end
end
