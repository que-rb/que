# frozen_string_literal: true

require 'spec_helper'

describe Que do
  describe ".default_queue" do
    it "should default to 'default'" do
      assert_equal 'default', Que.default_queue
    end

    it "should be overridable, and then revert to the default if set to nil" do
      assert_equal 'default', Que.default_queue
      Que.default_queue = 'my_queue'
      assert_equal 'my_queue', Que.default_queue
      Que.default_queue = nil
      assert_equal 'default', Que.default_queue
    end
  end

  describe ".pool" do
    it "should provide access to the connection pool" do
      assert_equal DEFAULT_QUE_POOL, Que.pool
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
    it "should accept a Sequel database" do
      Que.connection = DB

      DB.synchronize do |conn1|
        Que.checkout do |conn2|
          assert_equal conn1, conn2.wrapped_connection
        end
      end

      Que.checkout do |conn1|
        DB.synchronize do |conn2|
          assert_equal conn1.wrapped_connection, conn2
        end
      end
    end

    it "should accept the ActiveRecord class" do
      skip "ActiveRecord not loaded!" unless defined?(ActiveRecord)

      Que.connection = ActiveRecord

      ActiveRecord::Base.connection_pool.with_connection do |conn1|
        Que.checkout do |conn2|
          assert_equal conn1.raw_connection, conn2.wrapped_connection
        end
      end

      Que.checkout do |conn1|
        ActiveRecord::Base.connection_pool.with_connection do |conn2|
          assert_equal conn1.wrapped_connection, conn2.raw_connection
        end
      end
    end

    it "should accept a Pond instance" do
      pond = Pond.new &NEW_PG_CONNECTION
      Que.connection = pond

      pond.checkout do |conn1|
        Que.checkout do |conn2|
          assert_equal conn1, conn2.wrapped_connection
        end
      end

      Que.checkout do |conn1|
        pond.checkout do |conn2|
          assert_equal conn1.wrapped_connection, conn2
        end
      end
    end

    it "should accept a ConnectionPool instance" do
      cp = ConnectionPool.new &NEW_PG_CONNECTION

      Que.connection = cp

      cp.checkout do |conn1|
        Que.checkout do |conn2|
          assert_equal conn1, conn2.wrapped_connection
        end
      end

      Que.checkout do |conn1|
        cp.checkout do |conn2|
          assert_equal conn1.wrapped_connection, conn2
        end
      end
    end

    it "should accept nil" do
      Que.connection = nil

      error =
        assert_raises Que::Error do
          Que.pool
        end

      assert_match /Que connection not established!/, error.message
    end
  end

  describe "connection_proc=" do
    it "should define the logic that's used to retrieve a connection" do
      Que.connection_proc = proc { |&block| block.call(EXTRA_PG_CONNECTION) }
      Que.checkout do |c|
        assert_instance_of Que::Connection, c
        assert_equal EXTRA_PG_CONNECTION, c.wrapped_connection
      end
    end
  end
end
