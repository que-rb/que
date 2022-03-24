ALTER TABLE que_jobs ADD COLUMN kwargs JSONB NOT NULL DEFAULT '{}';
CREATE INDEX que_jobs_kwargs_gin_idx ON que_jobs USING gin (kwargs jsonb_path_ops);

DROP INDEX que_poll_idx;
ALTER INDEX que_poll_idx_with_job_schema_version RENAME TO que_poll_idx;

ALTER TABLE que_jobs ALTER COLUMN job_schema_version DROP DEFAULT;
ALTER TABLE que_jobs ALTER COLUMN job_schema_version SET NOT NULL;
