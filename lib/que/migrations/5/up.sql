ALTER TABLE que_jobs
  ADD COLUMN que_version INTEGER DEFAULT 1;
CREATE INDEX que_poll_idx_with_que_version ON que_jobs (que_version, queue, priority, run_at, id) WHERE (finished_at IS NULL AND expired_at IS NULL);