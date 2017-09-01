# frozen_string_literal: true

require 'spec_helper'

describe Que::Metajob do
  describe "<=>" do
    it "should sort appropriately" do
      old = Time.now - 30
      now = Time.now

      metajobs =
        [
          {priority: 1, run_at: old, id: 1},
          {priority: 1, run_at: old, id: 2},
          {priority: 1, run_at: now, id: 3},
          {priority: 1, run_at: now, id: 4},
          {priority: 2, run_at: old, id: 5},
          {priority: 2, run_at: old, id: 6},
          {priority: 2, run_at: now, id: 7},
          {priority: 2, run_at: now, id: 8},
        ].map { |sort_key| Que::Metajob.new(sort_key) }

      assert_equal metajobs, metajobs.shuffle.sort
    end
  end

  describe "priority_sufficient?" do
    it "should indicate whether the job's priority meets the given threshold" do
      mj = Que::Metajob.new(priority: 10, run_at: Time.now, id: 5)

      assert_equal true,   mj.priority_sufficient?(nil)
      assert_equal false,  mj.priority_sufficient?(5)
      assert_equal true,   mj.priority_sufficient?(10)
      assert_equal true,   mj.priority_sufficient?(15)
    end
  end
end
