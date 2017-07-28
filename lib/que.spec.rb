# frozen_string_literal: true

require 'spec_helper'

describe Que do
  describe ".default_queue" do
    it "should default to 'default'"

    it "should be overridable, and then revert to the default if set to nil"
  end

  describe ".pool" do
    it "should provide access to the connection pool" do
      assert_equal QUE_POOL, Que.pool
    end

    it "when no connection has been established should raise an error" do
      Que.connection_proc = nil

      error =
        assert_raises Que::Error do
          Que.pool
        end

      assert_match /Que connection not established!/, error.message
    end
  end

  describe "connection=" do
    it "should accept a Sequel database"

    it "should accept the ActiveRecord class"

    it "should accept a Pond instance"

    it "should accept a ConnectionPool instance"

    it "should accept nil"
  end

  describe "connection_proc=" do
    it "should define the logic that's used to retrieve a connection"
  end
end
