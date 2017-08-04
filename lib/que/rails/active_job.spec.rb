# frozen_string_literal: true

require 'spec_helper'

if defined?(::ActiveJob)
  describe "running jobs via ActiveJob" do
    before do
      class TestJobClass < ActiveJob::Base
        def run(*args)
          $args = args
        end

        # ActiveJob uses #perform but we use #run - to make sure that all the
        # spec cases that redefine #run still work, just make it an alias.
        def perform(*args)
          run(*args)
        end
      end
    end

    after do
      Object.send :remove_const, :TestJobClass
      $args = nil
    end

    let :job_queue do
      Que::JobQueue.new(maximum_size: 20)
    end

    let :result_queue do
      Que::ResultQueue.new
    end

    let :worker do
      Que::Worker.new \
        job_queue:    job_queue,
        result_queue: result_queue
    end

    def execute(*args)
      worker # Make sure worker is initialized.

      wrapper = TestJobClass.perform_later(*args)
      attrs = jobs_dataset.first!(id: wrapper.provider_job_id)

      job_queue.push(
        queue:    attrs[:queue],
        priority: attrs[:priority],
        run_at:   attrs[:run_at],
        id:       attrs[:id],
      )

      sleep_until! { result_queue.clear.map{|m| m.fetch(:id)} == [attrs[:id]] }
      attrs
    end

    it "should pass its arguments to the run method" do
      execute(1, 2)
      assert_equal [1, 2], $args
    end
  end
end
