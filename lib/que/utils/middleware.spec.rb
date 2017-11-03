# frozen_string_literal: true

require 'spec_helper'

describe Que::Utils::Middleware do
  describe "run_job_middleware" do
    it "when no job_middleware are defined should just run the block" do
      order = []

      Que.run_job_middleware(nil) { order << :called_block }

      assert_equal [:called_block], order
    end

    it "when one middleware is defined should run it" do
      order = []

      Que.job_middleware.push(
        -> (job, &block) {
          assert_equal 5, job
          order << :middleware_1_a
          block.call
          order << :middleware_1_b
        }
      )

      Que.run_job_middleware(5) { order << :called_block }

      assert_equal [
        :middleware_1_a,
        :called_block,
        :middleware_1_b,
      ], order
    end

    it "when multiple middleware are defined should run them" do
      order = []

      Que.job_middleware.push(
        -> (job, &block) {
          assert_equal 5, job
          order << :middleware_1_a
          block.call
          order << :middleware_1_b
        }
      )

      Que.job_middleware.push(
        -> (job, &block) {
          assert_equal 5, job
          order << :middleware_2_a
          block.call
          order << :middleware_2_b
        }
      )

      Que.run_job_middleware(5) { order << :called_block }

      assert_equal [
        :middleware_1_a,
        :middleware_2_a,
        :called_block,
        :middleware_2_b,
        :middleware_1_b,
      ], order
    end

    it "should support any callable object" do
      $order = []

      module MiddlewareTestModule
        def self.call(job)
          $order << :module_1
          yield
          $order << :module_2
        end
      end

      o = Object.new
      def o.call(job)
        $order << :object_1
        yield
        $order << :object_2
      end

      Que.job_middleware << MiddlewareTestModule << o

      assert_equal [], $order

      Que.run_job_middleware(5) { $order << :called_block }

      assert_equal [
        :module_1,
        :object_1,
        :called_block,
        :object_2,
        :module_2,
      ], $order

      $order = nil
    end
  end
end
