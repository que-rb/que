# frozen_string_literal: true

require 'spec_helper'

describe Que::Connection do
  let(:connection) { @connection }

  around do |&block|
    super() do
      QUE_POOLS[:pond].checkout do |conn|
        @connection = conn
        block.call
      end
    end
  end

  describe ".wrap()" do
    it "when given a Que connection should return it" do
      QUE_POOLS[:pond].checkout do |conn|
        assert_equal conn.object_id, Que::Connection.wrap(conn).object_id
      end
    end

    it "when given a PG connection should wrap it" do
      c = Que::Connection.wrap(EXTRA_PG_CONNECTION)
      assert_instance_of(Que::Connection, c)
      assert_equal EXTRA_PG_CONNECTION, c.wrapped_connection
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
          json_value: {key: 'value'},
          jsonb_value: {key: 'value'},
        },
        result.first,
      )
    end
  end
end
