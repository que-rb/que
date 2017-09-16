# frozen_string_literal: true

require 'spec_helper'

describe Que::ConnectionPool do
  # Some linting specs for all the pools we support natively.
  QUE_POOLS.each do |name, pool|
    describe "for a #{name} pool" do
      describe ".checkout" do
        it "should yield a Connection object" do
          pool.checkout do |conn|
            assert_instance_of Que::Connection, conn
          end
        end

        it "should be reentrant" do
          id1 = id2 = nil

          pool.checkout do |c1|
            pool.checkout do |c2|
              id1 = c1.object_id
              id2 = c2.object_id
            end
          end

          refute_nil id1
          refute_nil id2
          assert_equal id1, id2
        end
      end

      describe ".in_transaction?" do
        it "should delegate to the connection" do
          pool.checkout do |c|
            refute pool.in_transaction?
            c.execute "BEGIN"
            assert pool.in_transaction?
            c.execute "COMMIT"
            refute pool.in_transaction?
          end
        end
      end

      describe ".execute" do
        it "should delegate to the connection" do
          result = pool.execute("SELECT $1::jsonb::text AS j", [{blah: 3}])
          assert_equal [{j: "{\"blah\": 3}"}], result
        end

        it "should reuse the same connection when inside a checkout block" do
          pool.checkout do
            assert_equal(
              pool.execute("SELECT pg_backend_pid()"),
              pool.execute("SELECT pg_backend_pid()"),
            )
          end
        end
      end
    end
  end

  # Specs for theoretical, poorly-behaved pools
  describe ".checkout" do
    it "if the pool is not reentrant should raise an error" do
      # Borrow three PG connections from the pool.

      q1, q2 = Queue.new, Queue.new
      threads = Array.new(3) do
        Thread.new do
          DEFAULT_QUE_POOL.checkout do |c|
            q1.push(nil)
            q2.pop
            c
          end
        end
      end

      3.times { q1.pop }
      3.times { q2.push nil }

      connections = threads.map { |t| t.value.wrapped_connection }

      test_pool =
        Que::ConnectionPool.new do |&block|
          begin
            c = connections.pop
            block.call(c)
          ensure
            connections << c
          end
        end

      test_pool.checkout do |c|
        assert_instance_of Que::Connection, c
        assert_kind_of PG::Connection,  c.wrapped_connection

        assert_equal 2, connections.length

        error = assert_raises(Que::Error) { test_pool.checkout {} }
        assert_match /is not reentrant/, error.message
        assert_equal 2, connections.length
      end

      assert_equal 3, connections.length
    end

    it "if the pool yields an object that's already checked out should error" do
      test_pool = Que::ConnectionPool.new { |&block| block.call(EXTRA_PG_CONNECTION) }

      q1, q2 = Queue.new, Queue.new
      t =
        Thread.new do
          test_pool.checkout do |conn|
            assert_equal EXTRA_PG_CONNECTION, conn.wrapped_connection
            q1.push(nil)
            q2.pop
          end
        end

      q1.pop

      error = assert_raises(Que::Error) { test_pool.checkout {} }
      assert_match(
        /didn't synchronize access properly! \(entrance: #{EXTRA_PG_CONNECTION.backend_pid}\)/,
        error.message
      )

      q2.push(nil)
      error = assert_raises(Que::Error) { t.join }
      assert_match(
        /didn't synchronize access properly! \(exit: #{EXTRA_PG_CONNECTION.backend_pid}\)/,
        error.message
      )
    end
  end
end

describe "when wrapping a Sequel connection pool" do
  before do
    Que.pool = QUE_POOLS[:sequel]
  end

  it "should use the same connection that Sequel does" do
    pid1 = pid2 = nil

    SEQUEL_TEST_DB.synchronize do
      pid1 = SEQUEL_TEST_DB["SELECT pg_backend_pid()"].get
      pid2 = Que.execute("SELECT pg_backend_pid()").first[:pg_backend_pid]
    end

    assert_equal pid1, pid2

    pid1 = pid2 = nil

    Que.checkout do
      pid1 = SEQUEL_TEST_DB["SELECT pg_backend_pid()"].get
      pid2 = Que.execute("SELECT pg_backend_pid()").first[:pg_backend_pid]
    end

    assert_equal pid1, pid2
  end
end

if defined?(ActiveRecord)
  describe "when wrapping an ActiveRecord connection pool" do
    before do
      Que.pool = QUE_POOLS[:active_record]
    end

    it "should use the same connection that ActiveRecord does" do
      pid1 = pid2 = nil

      ActiveRecord::Base.connection_pool.with_connection do
        pid1 = ActiveRecord::Base.connection.select_value("select pg_backend_pid()").to_i
        pid2 = Que.execute("SELECT pg_backend_pid()").first[:pg_backend_pid]
      end

      assert_equal pid1, pid2

      pid1 = pid2 = nil

      Que.checkout do
        pid1 = ActiveRecord::Base.connection.select_value("select pg_backend_pid()").to_i
        pid2 = Que.execute("SELECT pg_backend_pid()").first[:pg_backend_pid]
      end

      assert_equal pid1, pid2
    end
  end
end
