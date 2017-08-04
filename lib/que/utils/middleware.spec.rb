# frozen_string_literal: true

require 'spec_helper'

describe Que::Utils::Middleware do
  describe "run_middleware" do
    it "when no middleware are defined should just run the block" do
      order = []

      Que.run_middleware(nil) { order << :called_block }

      assert_equal [:called_block], order
    end

    it "when one middleware is defined should run it" do
      order = []

      Que.middleware.push(
        -> (job, &block) {
          assert_equal 5, job
          order << :middleware_1_a
          block.call
          order << :middleware_1_b
        }
      )

      Que.run_middleware(5) { order << :called_block }

      assert_equal [
        :middleware_1_a,
        :called_block,
        :middleware_1_b,
      ], order
    end

    it "when multiple middleware are defined should run them" do
      order = []

      Que.middleware.push(
        -> (job, &block) {
          assert_equal 5, job
          order << :middleware_1_a
          block.call
          order << :middleware_1_b
        }
      )

      Que.middleware.push(
        -> (job, &block) {
          assert_equal 5, job
          order << :middleware_2_a
          block.call
          order << :middleware_2_b
        }
      )

      Que.run_middleware(5) { order << :called_block }

      assert_equal [
        :middleware_1_a,
        :middleware_2_a,
        :called_block,
        :middleware_2_b,
        :middleware_1_b,
      ], order
    end
  end
end
