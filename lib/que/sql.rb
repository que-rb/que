# frozen_string_literal: true

module Que
  SQL = {
    # Locks a job using a Postgres recursive CTE [1].
    #
    # As noted by the Postgres documentation, it may be slightly easier to
    # think about this expression as iteration rather than recursion, despite
    # the `RECURSION` nomenclature defined by the SQL standards committee.
    # Recursion is used here so that jobs in the table can be iterated one-by-
    # one until a lock can be acquired, where a non-recursive `SELECT` would
    # have the undesirable side-effect of locking multiple jobs at once. i.e.
    # Consider that the following would have the worker lock *all* unlocked
    # jobs:
    #
    #   SELECT (j).*, pg_try_advisory_lock((j).job_id) AS locked
    #   FROM que_jobs AS j;
    #
    # The CTE will initially produce an "anchor" from the non-recursive term
    # (i.e. before the `UNION`), and then use it as the contents of the
    # working table as it continues to iterate through `que_jobs` looking for
    # a lock. The jobs table has a sort on (priority, run_at, job_id) which
    # allows it to walk the jobs table in a stable manner. As noted above, the
    # recursion examines one job at a time so that it only ever acquires a
    # single lock.
    #
    # The recursion has two possible end conditions:
    #
    # 1. If a lock *can* be acquired, it bubbles up to the top-level `SELECT`
    #    outside of the `job` CTE which stops recursion because it is
    #    constrained with a `LIMIT` of 1.
    #
    # 2. If a lock *cannot* be acquired, the recursive term of the expression
    #    (i.e. what's after the `UNION`) will return an empty result set
    #    because there are no more candidates left that could possibly be
    #    locked. This empty result automatically ends recursion.
    #
    # Note that this query can be easily modified to lock any number of jobs
    # by tweaking the LIMIT clause in the main SELECT statement.
    #
    # [1] http://www.postgresql.org/docs/devel/static/queries-with.html
    #
    # Thanks to RhodiumToad in #postgresql for help with the original version
    # of the job lock CTE.
    :lock_job => %{
      WITH RECURSIVE jobs AS (
        SELECT (j).*, pg_try_advisory_lock((j).job_id) AS locked
        FROM (
          SELECT j
          FROM que_jobs AS j
          WHERE queue = $1::text
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
              WHERE queue = $1::text
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
      SELECT queue, priority, run_at, job_id, job_class, args, error_count
      FROM jobs
      WHERE locked
      LIMIT 1
    }.freeze,

    :check_job => %{
      SELECT 1 AS one
      FROM   que_jobs
      WHERE  queue    = $1::text
      AND    priority = $2::smallint
      AND    run_at   = $3::timestamptz
      AND    job_id   = $4::bigint
    }.freeze,

    :set_error => %{
      UPDATE que_jobs
      SET error_count = error_count + 1,
          run_at      = now() + $1::bigint * '1 second'::interval,
          last_error  = $2::text
      WHERE queue     = $3::text
      AND   priority  = $4::smallint
      AND   run_at    = $5::timestamptz
      AND   job_id    = $6::bigint
    }.freeze,

    :insert_job => %{
      INSERT INTO que_jobs
      (queue, priority, run_at, job_class, args)
      VALUES
      (coalesce($1, '')::text, coalesce($2, 100)::smallint, coalesce($3, now())::timestamptz, $4::text, coalesce($5, '[]')::json)
      RETURNING *
    }.freeze,

    :destroy_job => %{
      DELETE FROM que_jobs
      WHERE queue    = $1::text
      AND   priority = $2::smallint
      AND   run_at   = $3::timestamptz
      AND   job_id   = $4::bigint
    }.freeze,

    :job_stats => %{
      SELECT queue,
             job_class,
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
      GROUP BY queue, job_class
      ORDER BY count(*) DESC
    }.freeze,

    :worker_states_95 => %{
      SELECT que_jobs.*,
             pg.pid          AS pg_backend_pid,
             pg.state        AS pg_state,
             pg.state_change AS pg_state_changed_at,
             pg.query        AS pg_last_query,
             pg.query_start  AS pg_last_query_started_at,
             pg.xact_start   AS pg_transaction_started_at,
             pg.waiting      AS pg_waiting_on_lock
      FROM que_jobs
      JOIN (
        SELECT (classid::bigint << 32) + objid::bigint AS job_id, pg_stat_activity.*
        FROM pg_locks
        JOIN pg_stat_activity USING (pid)
        WHERE locktype = 'advisory'
      ) pg USING (job_id)
    }.freeze,

    :worker_states_96 => %{
      SELECT que_jobs.*,
             pg.pid                         AS pg_backend_pid,
             pg.state                       AS pg_state,
             pg.state_change                AS pg_state_changed_at,
             pg.query                       AS pg_last_query,
             pg.query_start                 AS pg_last_query_started_at,
             pg.xact_start                  AS pg_transaction_started_at,
             pg.wait_event_type IS NOT NULL AS pg_waiting_on_lock
      FROM que_jobs
      JOIN (
        SELECT (classid::bigint << 32) + objid::bigint AS job_id, pg_stat_activity.*
        FROM pg_locks
        JOIN pg_stat_activity USING (pid)
        WHERE locktype = 'advisory'
      ) pg USING (job_id)
    }.freeze,
  }.freeze
end
