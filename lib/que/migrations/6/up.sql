ALTER TABLE que_jobs
  ADD COLUMN kwargs JSONB NOT NULL DEFAULT '{}';

ALTER TABLE que_jobs
  ALTER COLUMN job_schema_version DROP DEFAULT;
