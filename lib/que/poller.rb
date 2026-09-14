# frozen_string_literal: true

module Que
  class Poller
    # The following SQL statement locks a batch of jobs using a Postgres
    # recursive CTE [1].
    #
    # As noted by the Postgres documentation, it may be slightly easier to
    # think about this expression as iteration rather than recursion, despite
    # the `RECURSION` nomenclature defined by the SQL standards committee.
    # Recursion is used here so that jobs in the table can be iterated one-by-
    # one until a lock can be acquired, where a non-recursive `SELECT` would
    # have the undesirable side-effect of locking jobs unnecessarily. For
    # example, the following might lock more than five jobs during execution:
    #
    #   SELECT (j).*, pg_try_advisory_lock((j).id) AS locked
    #   FROM public.que_jobs AS j
    #   LIMIT 5;
    #
    # The CTE will initially produce an "anchor" from the non-recursive term
    # (i.e. before the `UNION`), and then use it as the contents of the
    # working table as it continues to iterate through `que_jobs` looking for
    # locks. The jobs table has an index on (priority, run_at, id) which
    # allows it to walk the jobs table in a stable manner. As noted above, the
    # recursion examines/locks one job at a time. Every time the recursive
    # entry runs, it's output becomes the new contents of the working table,
    # and what was previously in the working table is appended to the final
    # result set. For more information on the basic workings of recursive
    # CTEs, see http://www.postgresql.org/docs/devel/static/queries-with.html
    #
    # The polling query is provided a JSONB hash of desired job priorities.
    # For example, if the locker has three workers free that can work a
    # priority less than 5, and two workers free that can work a priority less
    # than 10, the provided priority document is `{"5":3,"10":2}`. The query
    # uses this information to decide what jobs to lock - if only high-
    # priority workers were available, it wouldn't make sense to retrieve low-
    # priority jobs.
    #
    # As each job is retrieved from the table, it is passed to
    # lock_and_update_priorities() (which, for future flexibility, we define
    # as a temporary function attached to the connection rather than embedding
    # permanently into the DB schema). lock_and_update_priorities() attempts
    # to lock the given job and, if it is able to, updates the priorities
    # document to reflect that a job was available for that given priority.
    # When the priorities document is emptied (all the counts of desired jobs
    # for the various priorities have reached zero and been removed), the
    # recursive query returns an empty result and the recursion breaks. This
    # also happens if there aren't enough appropriate jobs in the jobs table.
    #
    # Also note the use of JOIN LATERAL to combine the job data with the
    # output of lock_and_update_priorities(). The naive approach would be to
    # write the SELECT as `SELECT (j).*, (lock_and_update_priorities(..., j)).*`,
    # but the asterisk-expansion of the latter composite row causes the function
    # to be evaluated twice, and to thereby take the advisory lock twice,
    # which complicates the later unlocking step.
    #
    # Thanks to RhodiumToad in #postgresql for help with the original
    # (simpler) version of the recursive job lock CTE.

    SQL[:poll_jobs] =
      %{
        WITH RECURSIVE jobs AS (
          SELECT
            (j).*,
            l.locked,
            l.remaining_priorities
          FROM (
            SELECT j
            FROM public.que_jobs AS j
            WHERE queue = $1::text
              AND job_schema_version = #{Que.job_schema_version}
              AND NOT id = ANY($2::bigint[])
              AND priority <= pg_temp.que_highest_remaining_priority($3::jsonb)
              AND run_at <= now()
              AND finished_at IS NULL AND expired_at IS NULL
            ORDER BY priority, run_at, id
            LIMIT 1
          ) AS t1
          JOIN LATERAL (SELECT * FROM pg_temp.lock_and_update_priorities($3::jsonb, j)) AS l ON true
          UNION ALL (
            SELECT
              (j).*,
              l.locked,
              l.remaining_priorities
            FROM (
              SELECT
                remaining_priorities,
                (
                  SELECT j
                  FROM public.que_jobs AS j
                  WHERE queue = $1::text
                    AND job_schema_version = #{Que.job_schema_version}
                    AND NOT id = ANY($2::bigint[])
                    AND priority <= pg_temp.que_highest_remaining_priority(jobs.remaining_priorities)
                    AND run_at <= now()
                    AND finished_at IS NULL AND expired_at IS NULL
                    AND (priority, run_at, id) >
                      (jobs.priority, jobs.run_at, jobs.id)
                  ORDER BY priority, run_at, id
                  LIMIT 1
                ) AS j

              FROM jobs
              WHERE jobs.id IS NOT NULL AND jobs.remaining_priorities != '{}'::jsonb
              LIMIT 1
            ) AS t1
            JOIN LATERAL (SELECT * FROM pg_temp.lock_and_update_priorities(remaining_priorities, j)) AS l ON true
          )
        )
        SELECT *
        FROM jobs
        WHERE locked
      }

    attr_reader \
      :connection,
      :queue,
      :poll_interval,
      :poll_interval_variance,
      :last_polled_at,
      :last_poll_satisfied,
      :next_poll_at

    def initialize(
      connection:,
      queue:,
      poll_interval:,
      poll_interval_variance:
    )
      @connection             = connection
      @queue                  = queue
      @poll_interval          = poll_interval
      @poll_interval_variance = poll_interval_variance

      @last_polled_at      = nil
      @last_poll_satisfied = nil
      @next_poll_at        = Time.now

      Que.internal_log :poller_instantiate, self do
        {
          backend_pid:            connection.backend_pid,
          queue:                  queue,
          poll_interval:          poll_interval,
          poll_interval_variance: poll_interval_variance,
        }
      end
    end

    def poll(
      priorities:,
      held_locks:
    )

      return unless should_poll?

      jobs =
        connection.execute_prepared(
          :poll_jobs,
          [
            @queue,
            "{#{held_locks.to_a.join(',')}}",
            JSON.dump(priorities),
          ]
        )

      @last_polled_at      = Time.now
      @last_poll_satisfied = poll_satisfied?(priorities, jobs)
      @next_poll_at        = last_polled_at +
                               poll_interval +
                               rand(-poll_interval_variance..poll_interval_variance)

      Que.internal_log :poller_polled, self do
        {
          queue:               @queue,
          locked:              jobs.count,
          priorities:          priorities,
          held_locks:          held_locks.to_a,
          newly_locked:        jobs.map { |key| key.fetch(:id) },
          last_polled_at:      last_polled_at,
          last_poll_satisfied: last_poll_satisfied,
          next_poll_at:        next_poll_at,
        }
      end

      jobs.map! { |job| Metajob.new(job) }
    end

    def should_poll?
      # polling is disabled for this queue
      return false if poll_interval.nil?

      # Never polled before?
      last_poll_satisfied.nil? ||
      # Plenty of jobs were available last time?
      last_poll_satisfied == true ||
      # It's due time to poll again regardless of the last poll's results?
      next_poll_at < Time.now
    end

    class << self
      # Manage some temporary infrastructure (specific to the connection) that
      # we'll use for polling. These could easily be created permanently in a
      # migration, but that'd require another migration if we wanted to tweak
      # them later.

      def setup(connection)
        connection.execute <<-SQL
          -- Temporary composite type we need for our queries to work.
          CREATE TYPE pg_temp.que_query_result AS (
            locked boolean,
            remaining_priorities jsonb
          );

          CREATE FUNCTION pg_temp.lock_and_update_priorities(priorities jsonb, job que_jobs)
          RETURNS pg_temp.que_query_result
          AS $$
            WITH
              -- Take the lock in a CTE because we want to use the result
              -- multiple times while only taking the lock once.
              lock_taken AS (
                SELECT pg_try_advisory_lock((job).id) AS taken
              ),
              relevant AS (
                SELECT priority, count
                FROM (
                  SELECT
                    key::smallint AS priority,
                    value::text::integer AS count
                  FROM jsonb_each(priorities)
                  ) t1
                WHERE priority >= (job).priority
                ORDER BY priority ASC
                LIMIT 1
              )
            SELECT
              (SELECT taken FROM lock_taken), -- R
              CASE (SELECT taken FROM lock_taken)
              WHEN false THEN
                -- Simple case - we couldn't lock the job, so don't update the
                -- priorities hash.
                priorities
              WHEN true THEN
                CASE count
                WHEN 1 THEN
                  -- Remove the priority from the JSONB doc entirely, rather
                  -- than leaving a zero entry in it.
                  priorities - priority::text
                ELSE
                  -- Decrement the value in the JSONB doc.
                  jsonb_set(
                    priorities,
                    ARRAY[priority::text],
                    to_jsonb(count - 1)
                  )
                END
              END
            FROM relevant
          $$
          STABLE
          LANGUAGE SQL;

          CREATE FUNCTION pg_temp.que_highest_remaining_priority(priorities jsonb) RETURNS smallint AS $$
            SELECT max(key::smallint) FROM jsonb_each(priorities)
          $$
          STABLE
          LANGUAGE SQL;
        SQL
      end

      def cleanup(connection)
        connection.execute <<-SQL
          DROP FUNCTION pg_temp.que_highest_remaining_priority(jsonb);
          DROP FUNCTION pg_temp.lock_and_update_priorities(jsonb, que_jobs);
          DROP TYPE pg_temp.que_query_result;
        SQL
      end
    end

    private

    def poll_satisfied?(priorities, jobs)
      lowest_priority = priorities.keys.max
      jobs.count >= priorities[lowest_priority]
    end
  end
end
