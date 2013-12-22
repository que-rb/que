module Que
  SQL = {
    # Thanks to RhodiumToad in #postgresql for the job lock CTE. It was
    # modified only slightly from his design.
    :lock_job => (
      <<-SQL
        WITH RECURSIVE cte AS (
          SELECT (job).*, pg_try_advisory_lock((job).job_id) AS locked
          FROM (
            SELECT job
            FROM que_jobs AS job
            WHERE run_at <= now()
            ORDER BY priority, run_at, job_id
            LIMIT 1
          ) AS t1
          UNION ALL (
            SELECT (job).*, pg_try_advisory_lock((job).job_id) AS locked
            FROM (
              SELECT (
               SELECT job
                FROM que_jobs AS job
                WHERE run_at <= now() AND (priority, run_at, job_id) > (cte.priority, cte.run_at, cte.job_id)
                ORDER BY priority, run_at, job_id
                LIMIT 1
              ) AS job
              FROM cte
              WHERE NOT cte.locked
              LIMIT 1
            ) AS t1
          )
        )
        SELECT priority, run_at, job_id, job_class, args, error_count
        FROM cte
        WHERE locked
        LIMIT 1
      SQL
    ).freeze,

    :check_job => (
      <<-SQL
        SELECT 1 AS one
        FROM   que_jobs
        WHERE  priority = $1::integer
        AND    run_at   = $2::timestamptz
        AND    job_id   = $3::bigint
      SQL
    ).freeze,

    :set_error => (
      <<-SQL
        UPDATE que_jobs
        SET error_count = $1::integer,
            run_at      = now() + $2::integer * '1 second'::interval,
            last_error  = $3::text
        WHERE priority  = $4::integer
        AND   run_at    = $5::timestamptz
        AND   job_id    = $6::bigint
      SQL
    ).freeze,

    :destroy_job => (
      <<-SQL
        DELETE FROM que_jobs
        WHERE priority = $1::integer
        AND   run_at   = $2::timestamptz
        AND   job_id   = $3::bigint
      SQL
    ).freeze,

    :create_table => (
      <<-SQL
        CREATE TABLE que_jobs
        (
          priority    integer     NOT NULL DEFAULT 1,
          run_at      timestamptz NOT NULL DEFAULT now(),
          job_id      bigserial   NOT NULL,
          job_class   text        NOT NULL,
          args        json        NOT NULL DEFAULT '[]'::json,
          error_count integer     NOT NULL DEFAULT 0,
          last_error  text,

          CONSTRAINT que_jobs_pkey PRIMARY KEY (priority, run_at, job_id)
        )
      SQL
    ).freeze
  }
end
