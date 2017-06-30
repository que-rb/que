# frozen_string_literal: true

require 'spec_helper'

describe Que::ConnectionPool do
  let :pool do
    QUE_POOL
  end

  describe ".execute" do
    it "should cast timestamp params correctly" do
      [
        Time.now.localtime,
        Time.now.utc,
      ].each do |t|
        # Round to the nearest microsecond, because Postgres doesn't get any
        # more accurate than that anyway. We could use Time.at(t.to_i, t.usec),
        # but that would lose timezone data :/

        time = Time.iso8601(t.iso8601(6))
        r = pool.execute("SELECT $1::timestamptz AS time", [time])
        assert_equal({time: time}, r.first)
      end
    end

    it "should typecast the results of the SQL statement" do
      result =
        pool.execute <<-SQL
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
