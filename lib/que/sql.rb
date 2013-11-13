module Que
  module SQL
    class << self
      def create_sql
        <<-SQL
CREATE TABLE que_jobs
(
  priority integer     NOT NULL DEFAULT 1,
  run_at   timestamptz NOT NULL DEFAULT now(),
  job_id   bigserial   NOT NULL,
  type     text        NOT NULL,
  args     json        NOT NULL DEFAULT '[]'::json,

  CONSTRAINT jobs_pkey PRIMARY KEY (priority, run_at, job_id)
);
        SQL
      end

      def drop_sql
        "DROP TABLE que_jobs;"
      end

      def clear_sql
        "DELETE FROM que_jobs;"
      end
    end
  end
end
