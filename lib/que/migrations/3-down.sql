ALTER TABLE que_jobs
  DROP CONSTRAINT que_jobs_pkey,
  DROP COLUMN queue,
  ALTER COLUMN priority TYPE integer,
  ADD CONSTRAINT que_jobs_pkey PRIMARY KEY (priority, run_at, job_id);
