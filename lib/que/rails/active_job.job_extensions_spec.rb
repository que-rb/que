# frozen_string_literal: true

require 'spec_helper'

if defined?(::ActiveJob)
  describe Que::ActiveJob::JobExtensions do
    describe "when used with a non-Que job queue" do
      before do
        class ApplicationJob < ActiveJob::Base
          include Que::ActiveJob::JobExtensions
        end

        class TestJobClass < ApplicationJob
        end

        ActiveJob::Base.queue_adapter = :inline
      end

      after do
        Object.send :remove_const, :ApplicationJob
        Object.send :remove_const, :TestJobClass
        $args = nil
        ActiveJob::Base.queue_adapter = :que
      end

      it "shouldn't cause problems" do
        # Fail if we add any methods to JobMethods without speccing them to make
        # sure they won't fail when used outside of Que.
        assert_equal(
          [
            :default_resolve_action,
            :destroy,
            :error_count,
            :expire,
            :finish,
            :handle_error,
            :que_target,
            :resolve_que_setting,
            :retry_in,
            :retry_in_default_interval,
          ],
          Que::JobMethods.private_instance_methods.sort,
        )

        TestJobClass.class_eval do
          def run(number, keyword_arg:)
            # Helper methods shouldn't cause problems.
            $results = [
              default_resolve_action,
              destroy,
              error_count,
              expire,
              finish,
              handle_error(nil),
              que_target,
              resolve_que_setting(:nonexistent),
              retry_in(6.minutes),
              retry_in_default_interval,
            ]

            $args = [number, keyword_arg]
          end
        end

        TestJobClass.perform_later(5, keyword_arg: "blah")

        assert_equal(
          [5, "blah"],
          $args,
        )

        assert_equal(
          [nil, nil, 0, nil, nil, nil, nil, nil, nil, nil],
          $results,
        )
      end
    end
  end
end
