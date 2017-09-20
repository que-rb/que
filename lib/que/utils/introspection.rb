# frozen_string_literal: true

# Tools for introspecting the state of the job queue.

module Que
  module Utils
    module Introspection
      SQL[:job_stats] =
        %{
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
          WHERE finished_at IS NULL AND expired_at IS NULL
          GROUP BY job_class
          ORDER BY count(*) DESC
        }

      def job_stats
        execute :job_stats
      end

      SQL[:job_states] =
        %{
          SELECT que_jobs.*,
                 pg.ruby_hostname,
                 pg.ruby_pid
          FROM public.que_jobs
          JOIN (
            SELECT (classid::bigint << 32) + objid::bigint AS id, que_lockers.*
            FROM pg_locks
            JOIN public.que_lockers USING (pid)
            WHERE locktype = 'advisory'
          ) pg USING (id)
        }

      def job_states
        execute :job_states
      end
    end
  end
end
