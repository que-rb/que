# frozen_string_literal: true

require 'spec_helper'

describe Que do
  it ".pool when no connection has been established should raise an error" do
    Que.connection_proc = nil
    proc{Que.pool}.should raise_error Que::Error, /Que connection not established!/
  end
end
