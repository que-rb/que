module Que
  SQL = {
    :get_job => %{
      SELECT *
      FROM que_jobs
      WHERE priority = $1::smallint
      AND   run_at   = $2::timestamptz
      AND   job_id   = $3::bigint
    },

    # Thanks to RhodiumToad in #postgresql for help with the poll_jobs CTE.

    # We don't retrieve all the job information in poll_jobs due to a race
    # condition that could result in jobs being run twice. If this query took
    # its MVCC snapshot while a job was being processed by another worker, but
    # didn't attempt the advisory lock until it was finished by that worker,
    # it could return a job that had already been completed. Once we have the
    # lock we know that a previous worker would have deleted the job by now,
    # so we use get_job to retrieve it. If it doesn't exist, no problem.

    :poll_jobs => %{
      WITH RECURSIVE jobs AS (
        SELECT (j).*, pg_try_advisory_lock((j).job_id) AS locked
        FROM (
          SELECT j
          FROM que_jobs AS j
          WHERE NOT job_id = ANY($1::integer[])
          AND run_at <= now()
          ORDER BY priority, run_at, job_id
          LIMIT 1
        ) AS t1
        UNION ALL (
          SELECT (j).*, pg_try_advisory_lock((j).job_id) AS locked
          FROM (
            SELECT (
              SELECT j
              FROM que_jobs AS j
              WHERE NOT job_id = ANY($1::integer[])
              AND run_at <= now()
              AND (priority, run_at, job_id) > (jobs.priority, jobs.run_at, jobs.job_id)
              ORDER BY priority, run_at, job_id
              LIMIT 1
            ) AS j
            FROM jobs
            WHERE jobs.job_id IS NOT NULL
            LIMIT 1
          ) AS t1
        )
      )
      SELECT priority, run_at, job_id
      FROM jobs
      WHERE locked
      LIMIT $2::integer
    },

    :reenqueue_job => %{
      WITH deleted_job AS (
        DELETE FROM que_jobs
          WHERE priority = $1::smallint
          AND   run_at   = $2::timestamptz
          AND   job_id   = $3::bigint
      )
      INSERT INTO que_jobs
      (priority, job_class, run_at, args)
      VALUES
      ($1::smallint, $4::text, $5::timestamptz, $6::json)
      RETURNING *
    },

    :check_job => %{
      SELECT 1 AS one
      FROM   que_jobs
      WHERE  priority = $1::smallint
      AND    run_at   = $2::timestamptz
      AND    job_id   = $3::bigint
    },

    :set_error => %{
      UPDATE que_jobs
      SET error_count = $1::integer,
          run_at      = now() + $2::bigint * '1 second'::interval,
          last_error  = $3::text
      WHERE priority  = $4::smallint
      AND   run_at    = $5::timestamptz
      AND   job_id    = $6::bigint
    },

    :insert_job => %{
      INSERT INTO que_jobs
      (priority, run_at, job_class, args)
      VALUES
      (coalesce($1, 100)::smallint, coalesce($2, now())::timestamptz, $3::text, coalesce($4, '[]')::json)
      RETURNING *
    },

    :destroy_job => %{
      DELETE FROM que_jobs
      WHERE priority = $1::smallint
      AND   run_at   = $2::timestamptz
      AND   job_id   = $3::bigint
    },

    :clean_lockers => %{
      DELETE FROM que_lockers
      WHERE pid = pg_backend_pid()
      OR pid NOT IN (SELECT pid FROM pg_stat_activity)
    },

    :register_locker => %{
      INSERT INTO que_lockers
      (pid, worker_count, ruby_pid, ruby_hostname, listening)
      VALUES
      (pg_backend_pid(), $1::integer, $2::integer, $3::text, $4::boolean);
    },

    :job_stats => %{
      SELECT job_class,
             count(*)                    AS count,
             count(locks.job_id)         AS count_working,
             sum((error_count > 0)::int) AS count_errored,
             max(error_count)            AS highest_error_count,
             min(run_at)                 AS oldest_run_at
      FROM que_jobs
      LEFT JOIN (
        SELECT (classid::bigint << 32) + objid::bigint AS job_id
        FROM pg_locks
        WHERE locktype = 'advisory'
      ) locks USING (job_id)
      GROUP BY job_class
      ORDER BY count(*) DESC
    },

    :job_states => %{
      SELECT que_jobs.*,
             pg.ruby_hostname,
             pg.ruby_pid
      FROM que_jobs
      JOIN (
        SELECT (classid::bigint << 32) + objid::bigint AS job_id, que_lockers.*
        FROM pg_locks
        JOIN que_lockers USING (pid)
        WHERE locktype = 'advisory'
      ) pg USING (job_id)
    },
  }

  # Clean up these statements so that logs are clearer.
  SQL.keys.each do |key|
    SQL[key] = SQL[key].strip.gsub(/\s+/, ' ').freeze
  end
  SQL.freeze
end
