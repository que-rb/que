DROP INDEX que_poll_idx_with_que_version;
ALTER TABLE que_jobs
  DROP COLUMN que_version;
