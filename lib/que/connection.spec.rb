# frozen_string_literal: true

require 'spec_helper'

describe Que::Connection do
  QUE_POOLS.each do |name, pool|
    describe "with a #{name} connection pool" do
      let(:connection) { @connection }

      around do |&block|
        super() do
          pool.checkout do |conn|
            @connection = conn
            block.call
          end
        end
      end

      let :fresh_connection, &NEW_PG_CONNECTION

      describe ".wrap()" do
        it "when given a Que connection should return it" do
          assert_equal connection.object_id, Que::Connection.wrap(connection).object_id
        end

        it "when given a PG connection should wrap it and set the wrapper as an attr on it" do
          assert_instance_of PG::Connection, fresh_connection

          c = Que::Connection.wrap(fresh_connection)
          assert_instance_of(Que::Connection, c)

          assert_equal fresh_connection, c.wrapped_connection
          assert_equal c, fresh_connection.instance_variable_get(:@que_wrapper)

          c2 = Que::Connection.wrap(fresh_connection)
          assert_equal c.object_id, c2.object_id
        end

        it "when given something else should raise an error" do
          error = assert_raises(Que::Error) do
            Que::Connection.wrap('no')
          end

          assert_equal "Unsupported input for Connection.wrap: String", error.message
        end
      end

      describe "in_transaction?" do
        it "should know when it is in a transaction" do
          refute connection.in_transaction?
          connection.execute "BEGIN"
          assert connection.in_transaction?
          connection.execute "COMMIT"
          refute connection.in_transaction?
          connection.execute "BEGIN"
          assert connection.in_transaction?
          connection.execute "ROLLBACK"
          refute connection.in_transaction?
        end
      end

      describe "next_notification and drain_notifications" do
        it "should allow access to pending notifications" do
          connection.execute "LISTEN test_queue"
          5.times { |i| DB.notify('test_queue', payload: i.to_s) }
          connection.execute("UNLISTEN *")

          assert_equal "0", connection.next_notification[:extra]
          connection.drain_notifications
          assert_nil connection.next_notification

          # Cleanup
          connection.drain_notifications
        end
      end

      describe "execute" do
        it "should cast JSON params correctly" do
          result = connection.execute("SELECT $1::jsonb::text AS j", [{blah: 3}])
          assert_equal [{j: "{\"blah\": 3}"}], result
        end

        it "should cast timestamp params correctly" do
          [
            Time.now.localtime,
            Time.now.utc,
          ].each do |t|
            # Round to the nearest microsecond, because Postgres doesn't get any
            # more accurate than that anyway. We could use Time.at(t.to_i, t.usec),
            # but that would lose timezone data :/

            time = Time.iso8601(t.iso8601(6))
            r = connection.execute("SELECT $1::timestamptz AS time", [time])
            assert_equal({time: time}, r.first)
          end
        end

        it "should typecast the results of the SQL statement" do
          result =
            connection.execute <<-SQL
              SELECT
                1                                   AS integer_value,
                1::bigint                           AS bigint_value,
                1::smallint                         AS smallint_value,
                'string'                            AS string_value,
                '2017-06-30T23:29:32Z'::timestamptz AS timestamp_value,
                2 + 2 = 4                           AS boolean_value,
                true                                AS true_value,
                false                               AS false_value,
                '{"key":"value"}'::json             AS json_value,
                '{"key":"value"}'::jsonb            AS jsonb_value
            SQL

          assert_equal(
            {
              integer_value: 1,
              bigint_value: 1,
              smallint_value: 1,
              string_value: 'string',
              timestamp_value: Time.iso8601('2017-06-30T23:29:32Z'),
              boolean_value: true,
              true_value: true,
              false_value: false,
              json_value: {key: 'value'},
              jsonb_value: {key: 'value'},
            },
            result.first,
          )
        end

        it "should run the sql_middleware around the request" do
          actions = []

          Que.sql_middleware.push(
            -> (sql, params, &block) {
              actions << :middleware_1_a << sql << params
              block.call
              actions << :middleware_1_b
              nil # Shouldn't matter what's returned.
            }
          )

          Que.sql_middleware.push(
            -> (sql, params, &block) {
              actions << :middleware_2_a << sql << params
              block.call
              actions << :middleware_2_b
              nil # Shouldn't matter what's returned.
            }
          )

          r = Que.execute("SELECT 1 AS a")
          assert_equal [{a: 1}], r
          assert_equal [:middleware_1_a, "SELECT 1 AS a", [], :middleware_2_a, "SELECT 1 AS a", [], :middleware_2_b, :middleware_1_b], actions
          actions.clear

          r = Que.execute("SELECT 1 + $1 AS a", [2])
          assert_equal [{a: 3}], r
          assert_equal [:middleware_1_a, "SELECT 1 + $1 AS a", [2], :middleware_2_a, "SELECT 1 + $1 AS a", [2], :middleware_2_b, :middleware_1_b], actions
        end
      end

      describe "execute_prepared" do
        def assert_statement_prepared
          assert_equal [], fresh_connection.describe_prepared("que_check_job").to_a
        end

        def refute_statement_prepared
          assert_raises(PG::InvalidSqlStatementName) { fresh_connection.describe_prepared("que_check_job") }
        end

        it "should prepare the given SQL query before running it, if necessary" do
          c = Que::Connection.wrap(fresh_connection)
          refute_statement_prepared

          assert_equal [], c.execute_prepared(:check_job, [1])
          assert_statement_prepared

          assert_equal [], c.execute_prepared(:check_job, [1])
          assert_statement_prepared
        end

        it "should defer to execute() if use_prepared_statements is false" do
          Que.use_prepared_statements = false

          c = Que::Connection.wrap(fresh_connection)
          refute_statement_prepared

          assert_equal [], c.execute_prepared(:check_job, [1])
          refute_statement_prepared

          assert_equal [], c.execute_prepared(:check_job, [1])
          refute_statement_prepared
        end

        it "should defer to execute() when in a transaction" do
          c = Que::Connection.wrap(fresh_connection)
          refute_statement_prepared

          c.execute("BEGIN")
          assert_equal [], c.execute_prepared(:check_job, [1])
          c.execute("COMMIT")

          refute_statement_prepared
        end

        # ActiveRecord can do this sometimes when there's a reconnection.
        it "if the connection doesn't actually have the statement prepared should recover" do
          c = Que::Connection.wrap(fresh_connection)
          c.instance_variable_get(:@prepared_statements).add(:check_job)
          refute_statement_prepared

          assert_equal [], c.execute_prepared(:check_job, [1])
          assert_statement_prepared

          messages = logged_messages.select{|m| m[:event] == "reprepare_statement"}
          assert_equal 1, messages.length

          message = messages.first
          assert_equal "check_job", message[:command]
        end
      end
    end
  end
end
