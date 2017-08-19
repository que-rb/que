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

    SQL[:poll_jobs] =
      %{
        WITH RECURSIVE jobs AS (
          SELECT (j).*, pg_try_advisory_lock((j).id) AS locked
          FROM (
            SELECT j
            FROM public.que_jobs AS j
            WHERE queue = $1::text
              AND NOT id = ANY($2::integer[])
              AND run_at <= now()
              AND finished_at IS NULL
            ORDER BY priority, run_at, id
            LIMIT 1
          ) AS t1
          UNION ALL (
            SELECT (j).*, pg_try_advisory_lock((j).id) AS locked
            FROM (
              SELECT (
                SELECT j
                FROM public.que_jobs AS j
                WHERE queue = $1::text
                  AND NOT id = ANY($2::integer[])
                  AND run_at <= now()
                  AND finished_at IS NULL
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
        SELECT *
        FROM jobs
        WHERE locked
        LIMIT $3::integer
      }

    attr_reader \
      :connection,
      :queue,
      :poll_interval,
      :last_polled_at,
      :last_poll_satisfied

    def initialize(
      connection:,
      queue:,
      poll_interval:
    )
      @connection          = connection
      @queue               = queue
      @poll_interval       = poll_interval
      @last_polled_at      = nil
      @last_poll_satisfied = nil

      Que.internal_log :poller_instantiate, self do
        {
          backend_pid:   connection.backend_pid,
          queue:         queue,
          poll_interval: poll_interval,
        }
      end
    end

    def poll(limit, held_locks:)
      return unless should_poll?

      jobs =
        connection.execute(
          :poll_jobs,
          [
            @queue,
            "{#{held_locks.to_a.join(',')}}",
            limit,
          ]
        )

      jobs.each{|j| j[:run_at] = j[:run_at].utc.iso8601(6)}
      jobs.each &:freeze

      @last_polled_at      = Time.now
      @last_poll_satisfied = limit == jobs.count

      Que.internal_log :poller_polled, self do
        {
          queue:        @queue,
          limit:        limit,
          locked:       jobs.count,
          held_locks:   held_locks.to_a,
          newly_locked: jobs.map { |key| key.fetch(:id) },
        }
      end

      jobs.map! do |job|
        Metajob.new(
          sort_key: {
            queue:    job[:queue],
            priority: job[:priority],
            run_at:   job[:run_at],
            id:       job[:id],
          }.freeze,
          is_locked: true,
          source: :poller,
          job: job,
        )
      end
    end

    def should_poll?
      # Never polled before?
      last_poll_satisfied.nil? ||
      # Plenty of jobs were available last time?
      last_poll_satisfied == true ||
      poll_interval_elapsed?
    end

    def poll_interval_elapsed?
      return unless interval = poll_interval
      (Time.now - last_polled_at) > interval
    end
  end
end
