# frozen_string_literal: true

module Que
  module ActiveSupport
    module JobMiddleware
      def self.call(job)
        labels = {
          job_class: job.que_attrs[:job_class],
          priority: job.que_attrs[:priority],
          queue: job.que_attrs[:queue],
          latency: job.que_attrs[:latency],
        }

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        yield
      ensure
        ::ActiveSupport::Notifications.publish(
          "que_job.worked",
          started,
          Process.clock_gettime(Process::CLOCK_MONOTONIC),
          labels.merge(error: !!job.que_error.present?),
        )
      end
    end
  end
end
