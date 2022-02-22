ALTER TABLE que_jobs
  ADD COLUMN kwargs JSONB NOT NULL DEFAULT '{}';

CREATE INDEX que_jobs_kwargs_gin_idx ON que_jobs USING gin (kwargs jsonb_path_ops);

ALTER TABLE que_jobs
  ALTER COLUMN job_schema_version DROP DEFAULT;
