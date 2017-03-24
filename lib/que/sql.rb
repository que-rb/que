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
    #   SELECT (j).*, pg_try_advisory_lock((j).id) AS locked
    #   FROM public.que_jobs AS j;
    #
    # The CTE will initially produce an "anchor" from the non-recursive term
    # (i.e. before the `UNION`), and then use it as the contents of the
    # working table as it continues to iterate through `que_jobs` looking for
    # a lock. The jobs table has a sort on (priority, run_at, id) which
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
    # Also note that we don't retrieve all the job information in poll_jobs
    # due to a race condition that could result in jobs being run twice. If
    # this query took its MVCC snapshot while a job was being processed by
    # another worker, but didn't attempt the advisory lock until it was
    # finished by that worker, it could return a job that had already been
    # completed. Once we have the lock we know that a previous worker would
    # have deleted the job by now, so we use get_job to retrieve it. If it
    # doesn't exist, no problem.
    #
    # [1] http://www.postgresql.org/docs/devel/static/queries-with.html
    #
    # Thanks to RhodiumToad in #postgresql for help with the original version
    # of the job lock CTE.

    poll_jobs: %{
      WITH RECURSIVE jobs AS (
        SELECT (j).*, pg_try_advisory_lock((j).id) AS locked
        FROM (
          SELECT j
          FROM public.que_jobs AS j
          WHERE NOT id = ANY($1::integer[])
          AND run_at <= now()
          ORDER BY priority, run_at, id
          LIMIT 1
        ) AS t1
        UNION ALL (
          SELECT (j).*, pg_try_advisory_lock((j).id) AS locked
          FROM (
            SELECT (
              SELECT j
              FROM public.que_jobs AS j
              WHERE NOT id = ANY($1::integer[])
              AND run_at <= now()
              AND (priority, run_at, id) >
                (jobs.priority, jobs.run_at, jobs.id)
              ORDER BY priority, run_at, id
              LIMIT 1
            ) AS j
            FROM jobs
            WHERE jobs.id IS NOT NULL
            LIMIT 1
          ) AS t1
        )
      )
      SELECT priority, run_at, id
      FROM jobs
      WHERE locked
      LIMIT $2::integer
    },

    get_job: %{
      SELECT *
      FROM public.que_jobs
      WHERE priority = $1::smallint
      AND   run_at   = $2::timestamptz
      AND   id       = $3::bigint
    },

    reenqueue_job: %{
      WITH deleted_job AS (
        DELETE FROM public.que_jobs
          WHERE priority = $1::smallint
          AND   run_at   = $2::timestamptz
          AND   id       = $3::bigint
      )
      INSERT INTO public.que_jobs
      (priority, job_class, run_at, args)
      VALUES
      ($1::smallint, $4::text, $5::timestamptz, $6::json)
      RETURNING *
    },

    set_error: %{
      UPDATE public.que_jobs
      SET error_count = error_count + 1,
          run_at      = now() + $1::bigint * '1 second'::interval,
          last_error  = $2::text
      WHERE priority  = $3::smallint
      AND   run_at    = $4::timestamptz
      AND   id        = $5::bigint
    },

    insert_job: %{
      INSERT INTO public.que_jobs
      (priority, run_at, job_class, args)
      VALUES
      (
        coalesce($1, 100)::smallint,
        coalesce($2, now())::timestamptz,
        $3::text,
        coalesce($4, '[]')::json
      )
      RETURNING *
    },

    destroy_job: %{
      DELETE FROM public.que_jobs
      WHERE priority = $1::smallint
      AND   run_at   = $2::timestamptz
      AND   id       = $3::bigint
    },

    clean_lockers: %{
      DELETE FROM public.que_lockers
      WHERE pid = pg_backend_pid()
      OR pid NOT IN (SELECT pid FROM pg_stat_activity)
    },

    register_locker: %{
      INSERT INTO public.que_lockers
      (pid, worker_count, ruby_pid, ruby_hostname, listening)
      VALUES
      (pg_backend_pid(), $1::integer, $2::integer, $3::text, $4::boolean);
    },

    job_stats: %{
      SELECT job_class,
             count(*)                    AS count,
             count(locks.id)             AS count_working,
             sum((error_count > 0)::int) AS count_errored,
             max(error_count)            AS highest_error_count,
             min(run_at)                 AS oldest_run_at
      FROM public.que_jobs
      LEFT JOIN (
        SELECT (classid::bigint << 32) + objid::bigint AS id
        FROM pg_locks
        WHERE locktype = 'advisory'
      ) locks USING (id)
      GROUP BY job_class
      ORDER BY count(*) DESC
    },

    job_states: %{
      SELECT que_jobs.*,
             pg.ruby_hostname,
             pg.ruby_pid
      FROM public.que_jobs
      JOIN (
        SELECT (classid::bigint << 32) + objid::bigint AS id, que_lockers.*
        FROM pg_locks
        JOIN que_lockers USING (pid)
        WHERE locktype = 'advisory'
      ) pg USING (id)
    },
  }

  # Clean up these statements so that logs are clearer.
  SQL.keys.each do |key|
    SQL[key] = SQL[key].strip.gsub(/\s+/, ' ').freeze
  end
  SQL.freeze
end
