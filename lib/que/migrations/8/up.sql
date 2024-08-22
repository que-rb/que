-- Add 'first_run_at' column to 'que_jobs'. The 'first_run_at' column will store the timestamp with time zone (timestamptz) 
-- of the initial scheduled execution time for que jobs. The column default is set to now, but realistically this will always 
-- be defaulted to the initial run_at value. This enhancement helps re-trace the execution of the job when reviewing failures.

ALTER TABLE que_jobs
  ADD COLUMN first_run_at timestamptz NOT NULL DEFAULT now();


-- This view extends the functionality of the que job management system by providing an enriched view of que jobs. 
-- It combines data from the 'que_jobs' table and the 'pg_locks' table to present a comprehensive overview of que jobs, 
-- including their status, associated information, and locking details. The view is designed to facilitate the monitoring
--  and management of que jobs, allowing you to track job statuses, locking details, and job-related information.

-- Columns:
-- - lock_id: Unique identifier for the lock associated with the job.
-- - que_locker_pid: Process ID (PID) of the que job locker.
-- - sub_class: The job class extracted from the job arguments.
-- - updated_at: The most recent timestamp among 'run_at,' 'expired_at,' and 'finished_at.'
-- - status: The status of the job, which can be 'running,' 'completed,' 'failed,' 'errored,' 'queued,' or 'scheduled.'

CREATE OR REPLACE VIEW public.que_jobs_ext
AS
SELECT
    locks.id AS lock_id,
    locks.pid as que_locker_pid,
    (que_jobs.args -> 0) ->> 'job_class'::text AS sub_class,
    greatest(run_at, expired_at, finished_at) as updated_at,

    case
      when locks.id is not null then 'running'
      when finished_at is not null then 'completed'
      when expired_at is not null then 'failed'
      when error_count > 0 then 'errored'
      when run_at < now() then 'queued'
      else 'scheduled'
    end as status,

    -- que_jobs.*:
    que_jobs.id,
    que_jobs.priority,
    que_jobs.run_at,
    que_jobs.first_run_at,
    que_jobs.job_class,
    que_jobs.error_count,
    que_jobs.last_error_message,
    que_jobs.queue,
    que_jobs.last_error_backtrace,
    que_jobs.finished_at,
    que_jobs.expired_at,
    que_jobs.args,
    que_jobs.data,
    que_jobs.kwargs,
    que_jobs.job_schema_version

  FROM que_jobs
    LEFT JOIN (
      SELECT
        (classid::bigint << 32) + objid::bigint AS id
        , pid
          FROM  pg_locks
          WHERE pg_locks.locktype = 'advisory'::text) locks USING (id);