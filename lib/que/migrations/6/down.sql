DROP INDEX que_jobs_kwargs_gin_idx;

ALTER TABLE que_jobs
  DROP COLUMN kwargs;

ALTER TABLE que_jobs
  ALTER COLUMN job_schema_version SET DEFAULT 1;
