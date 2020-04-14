# frozen_string_literal: true

module Que
  module ActiveRecord
    class Model < ::ActiveRecord::Base
      self.table_name = 'public.que_jobs'

      t = arel_table

      scope :errored,     -> { where(t[:error_count].gt(0)) }
      scope :not_errored, -> { where(t[:error_count].eq(0)) }

      scope :expired,     -> { where(t[:expired_at].not_eq(nil)) }
      scope :not_expired, -> { where(t[:expired_at].eq(nil)) }

      scope :finished,     -> { where(t[:finished_at].not_eq(nil)) }
      scope :not_finished, -> { where(t[:finished_at].eq(nil)) }

      scope :scheduled,     -> { where(t[:run_at].gt  (Arel.sql("now()"))) }
      scope :not_scheduled, -> { where(t[:run_at].lteq(Arel.sql("now()"))) }

      scope :ready,     -> { not_errored.not_expired.not_finished.not_scheduled }
      scope :not_ready, -> { where(t[:error_count].gt(0).or(t[:expired_at].not_eq(nil)).or(t[:finished_at].not_eq(nil)).or(t[:run_at].gt(Arel.sql("now()")))) }

      class << self
        def by_job_class(job_class)
          job_class = job_class.name if job_class.is_a?(Class)
          job_class_doc = "[{\"job_class\": \"#{job_class}\"}]"
          where(
            "que_jobs.job_class = ? OR (que_jobs.job_class = 'ActiveJob::QueueAdapters::QueAdapter::JobWrapper' AND que_jobs.args @> ?)",
            job_class, job_class_doc,
          )
        end

        def by_queue(queue)
          where(arel_table[:queue].eq(queue))
        end

        def by_tag(tag)
          where("que_jobs.data @> ?", JSON.dump(tags: [tag]))
        end

        def by_args(*args, **kwargs)
          where("que_jobs.args @> ? AND que_jobs.kwargs @> ?", JSON.dump(args), JSON.dump(kwargs))
        end
      end
    end
  end
end
