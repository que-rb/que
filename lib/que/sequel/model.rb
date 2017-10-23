# frozen_string_literal: true

module Que
  module Sequel
    QUALIFIED_TABLE = ::Sequel.qualify(:public, :que_jobs)

    class Model < ::Sequel::Model(QUALIFIED_TABLE)
      dataset_module do
        conditions = {
          errored:   ::Sequel.qualify(QUALIFIED_TABLE, :error_count) > 0,
          expired:   ::Sequel.~(::Sequel.qualify(QUALIFIED_TABLE, :expired_at)  => nil),
          finished:  ::Sequel.~(::Sequel.qualify(QUALIFIED_TABLE, :finished_at) => nil),
          scheduled: ::Sequel.qualify(QUALIFIED_TABLE, :run_at) > ::Sequel::CURRENT_TIMESTAMP,
        }

        conditions.each do |name, condition|
          subset           name,  condition
          subset :"not_#{name}", ~condition
        end

        subset :ready,     conditions.values.map(&:~).inject{|a, b| a & b}
        subset :not_ready, conditions.values.         inject{|a, b| a | b}

        def by_job_class(job_class)
          job_class = job_class.name if job_class.is_a?(Class)
          where(
            ::Sequel.|(
              {::Sequel.qualify(QUALIFIED_TABLE, :job_class) => job_class},
              {
                ::Sequel.qualify(QUALIFIED_TABLE, :job_class) => "ActiveJob::QueueAdapters::QueAdapter::JobWrapper",
                ::Sequel.lit("public.que_jobs.args->0->>'job_class'") => job_class,
              }
            )
          )
        end

        def by_queue(queue)
          where(::Sequel.qualify(QUALIFIED_TABLE, :queue) => queue)
        end

        def by_tag(tag)
          where(::Sequel.lit("public.que_jobs.data @> ?", JSON.dump(tags: [tag])))
        end

        def by_args(*args)
          where(::Sequel.lit("public.que_jobs.args @> ?", JSON.dump(args)))
        end
      end
    end
  end
end
