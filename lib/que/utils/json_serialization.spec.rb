# frozen_string_literal: true

require 'spec_helper'

describe Que::Utils::JSONSerialization do
  describe "serialize_json" do
    it "should convert a hash to JSON" do
      assert_equal(
        "{\"blah\":3}",
        Que.serialize_json({blah: 3}),
      )
    end

    it "should convert an array to JSON" do
      assert_equal(
        "[{\"blah\":3}]",
        Que.serialize_json([{blah: 3}]),
      )
    end
  end

  describe "deserialize_json" do
    it "should deserialize a JSON doc, symbolizing the keys" do
      assert_equal(
        {blah: 3},
        Que.deserialize_json("{\"blah\":3}"),
      )
    end
  end
end
