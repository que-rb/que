DROP TRIGGER que_job_notify ON que_jobs;
DROP FUNCTION que_job_notify();
DROP TABLE que_lockers;

DROP INDEX que_jobs_poll_idx;

ALTER TABLE que_jobs
  RENAME COLUMN id TO job_id;

ALTER TABLE que_jobs
  DROP CONSTRAINT que_jobs_pkey,
  ADD COLUMN queue TEXT NOT NULL DEFAULT '',
  ADD CONSTRAINT que_jobs_pkey PRIMARY KEY (queue, priority, run_at, job_id);
