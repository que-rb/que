DROP INDEX que_jobs_kwargs_gin_idx;
ALTER TABLE que_jobs DROP COLUMN kwargs;

ALTER INDEX que_poll_idx RENAME TO que_poll_idx_with_job_schema_version;
CREATE INDEX que_poll_idx ON que_jobs (queue, priority, run_at, id) WHERE (finished_at IS NULL AND expired_at IS NULL);

ALTER TABLE que_jobs ALTER COLUMN job_schema_version SET DEFAULT 1;
ALTER TABLE que_jobs ALTER COLUMN job_schema_version DROP NOT NULL;
