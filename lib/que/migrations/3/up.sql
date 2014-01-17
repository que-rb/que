ALTER TABLE que_jobs
  DROP CONSTRAINT que_jobs_pkey,
  ALTER COLUMN priority TYPE smallint,
  ADD COLUMN queue TEXT NOT NULL DEFAULT '',
  ADD CONSTRAINT que_jobs_pkey PRIMARY KEY (queue, priority, run_at, job_id);
