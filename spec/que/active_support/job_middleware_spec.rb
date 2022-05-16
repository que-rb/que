# frozen_string_literal: true

require 'spec_helper'

if defined?(::ActiveSupport)
  require 'que/active_support/job_middleware'

  describe Que::ActiveSupport::JobMiddleware do
    let(:job) do
      Que::Job.new(
        job_class: "Foo",
        priority: 100,
        queue: "foo_queue",
        latency: 100,
      )
    end

    let(:labels) do
      {
        job_class: "Foo",
        priority: 100,
        queue: "foo_queue",
        latency: 100,
      }
    end

    it "records metrics" do
      called = false
      ::ActiveSupport::Notifications.subscribe("que_job.worked") do |message, started, finished, metric_labels|
        assert_equal "que_job.worked", message
        assert started != nil
        assert finished != nil
        assert_equal labels.merge(error: false), metric_labels
        called = true
      end

      Que::ActiveSupport::JobMiddleware.call(job) { }

      assert_equal true, called
    end
  end
end
