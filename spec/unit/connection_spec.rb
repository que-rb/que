# frozen_string_literal: true

require 'spec_helper'

describe Que do
  it ".connection= with an unsupported connection should raise an error" do
    proc{Que.connection = "ferret"}.should raise_error RuntimeError, /Que connection not recognized: "ferret"/
  end

  it ".adapter when no connection has been established should raise an error" do
    Que.connection = nil
    proc{Que.adapter}.should raise_error RuntimeError, /Que connection not established!/
  end
end
