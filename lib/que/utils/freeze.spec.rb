# frozen_string_literal: true

require 'spec_helper'

describe Que::Utils::Freeze do
  describe 'recursively_freeze' do
    it "should freeze whatever it's given" do
      sub_hash   = {blah: 1}
      sub_array  = [1, 2, 3]
      sub_string = 'blah'.dup
      input      = [{hash: sub_hash, array: sub_array, string: sub_string}]

      output = Que.recursively_freeze(input)
      assert input.frozen?
      assert sub_hash.frozen?
      assert sub_array.frozen?
      assert sub_string.frozen?
      assert_equal input.object_id, output.object_id
    end
  end
end
