ALTER TABLE que_jobs
  ADD COLUMN retryable BOOL DEFAULT TRUE,
  ADD COLUMN failed_at TIMESTAMPTZ;
UPDATE que_jobs SET retryable = true;
