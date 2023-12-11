ALTER TABLE que_jobs
ALTER COLUMN run_at SET DEFAULT clock_timestamp();
