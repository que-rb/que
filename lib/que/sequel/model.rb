# frozen_string_literal: true

::Sequel.extension :pg_json_ops

module Que
  module Sequel
    QUALIFIED_TABLE = ::Sequel.qualify(:public, :que_jobs)

    class Model < ::Sequel::Model(QUALIFIED_TABLE)
      dataset_module do
        conditions = {
          errored:   QUALIFIED_TABLE[:error_count] > 0,
          expired:   QUALIFIED_TABLE[:expired_at] !~ nil,
          finished:  QUALIFIED_TABLE[:finished_at] !~ nil,
          scheduled: QUALIFIED_TABLE[:run_at] > ::Sequel::CURRENT_TIMESTAMP,
        }

        conditions.each do |name, condition|
          subset           name,  condition
          subset :"not_#{name}", ~condition
        end

        subset :ready,     conditions.values.map(&:~).inject(:&)
        subset :not_ready, conditions.values.         inject(:|)

        def by_job_class(job_class)
          job_class = job_class.name if job_class.is_a?(Class)
          where(
            (QUALIFIED_TABLE[:job_class] =~ job_class) |
              (QUALIFIED_TABLE[:job_class] =~ "ActiveJob::QueueAdapters::QueAdapter::JobWrapper") &
              (QUALIFIED_TABLE[:args].pg_jsonb[0].get_text("job_class") =~ job_class)
          )
        end

        def by_queue(queue)
          where(QUALIFIED_TABLE[:queue] => queue)
        end

        def by_tag(tag)
          where(QUALIFIED_TABLE[:data].pg_jsonb.contains(JSON.dump(tags: [tag])))
        end

        def by_args(*args, **kwargs)
          where(
            QUALIFIED_TABLE[:args].pg_jsonb.contains(JSON.dump(args)) &
            QUALIFIED_TABLE[:kwargs].pg_jsonb.contains(JSON.dump(kwargs))
          ) 
        end
      end
    end
  end
end
