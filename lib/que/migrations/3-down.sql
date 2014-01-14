ALTER TABLE que_jobs DROP COLUMN queue;
ALTER TABLE que_jobs ADD CONSTRAINT que_jobs_pkey PRIMARY KEY (priority, run_at, job_id);
