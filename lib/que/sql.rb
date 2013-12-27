module Que
  SQL = {
    # Thanks to RhodiumToad in #postgresql for help with the job lock CTE.
    :lock_job => %{
      WITH RECURSIVE job AS (
        SELECT (j).*, pg_try_advisory_lock((j).job_id) AS locked
        FROM (
          SELECT j
          FROM que_jobs AS j
          WHERE run_at <= now()
          ORDER BY priority, run_at, job_id
          LIMIT 1
        ) AS t1
        UNION ALL (
          SELECT (j).*, pg_try_advisory_lock((j).job_id) AS locked
          FROM (
            SELECT (
             SELECT j
              FROM que_jobs AS j
              WHERE run_at <= now() AND (priority, run_at, job_id) > (job.priority, job.run_at, job.job_id)
              ORDER BY priority, run_at, job_id
              LIMIT 1
            ) AS j
            FROM job
            WHERE NOT job.locked
            LIMIT 1
          ) AS t1
        )
      )
      SELECT priority, run_at, job_id, job_class, args, error_count
      FROM job
      WHERE locked
      LIMIT 1
    }.freeze,

    :check_job => %{
      SELECT 1 AS one
      FROM   que_jobs
      WHERE  priority = $1::integer
      AND    run_at   = $2::timestamptz
      AND    job_id   = $3::bigint
    }.freeze,

    :set_error => %{
      UPDATE que_jobs
      SET error_count = $1::integer,
          run_at      = now() + $2::integer * '1 second'::interval,
          last_error  = $3::text
      WHERE priority  = $4::integer
      AND   run_at    = $5::timestamptz
      AND   job_id    = $6::bigint
    }.freeze,

    :destroy_job => %{
      DELETE FROM que_jobs
      WHERE priority = $1::integer
      AND   run_at   = $2::timestamptz
      AND   job_id   = $3::bigint
    }.freeze,

    :create_table => %{
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
    }.freeze
  }
end
