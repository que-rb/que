ALTER TABLE que_jobs RESET (
  fillfactor,
  autovacuum_vacuum_scale_factor,
  autovacuum_vacuum_threshold
);

DROP TRIGGER que_job_notify ON que_jobs;
DROP FUNCTION que_job_notify();
DROP TABLE que_lockers;

ALTER TABLE que_jobs
  RENAME COLUMN id TO job_id;

ALTER SEQUENCE que_jobs_id_seq RENAME TO que_jobs_job_id_seq;

ALTER TABLE que_jobs
  RENAME COLUMN last_error_message TO last_error;

ALTER TABLE que_jobs
  DROP CONSTRAINT queue_length,
  DROP CONSTRAINT run_at_valid,
  ADD COLUMN args JSON;

UPDATE que_jobs
  SET args = (data->'args')::json,
  queue = CASE queue WHEN 'default' THEN '' ELSE queue END,
  last_error = last_error || E'\n' || last_error_backtrace;

ALTER TABLE que_jobs
  DROP COLUMN last_error_backtrace,
  DROP COLUMN data,
  ALTER COLUMN args SET NOT NULL,
  ALTER COLUMN args SET DEFAULT '[]',
  ALTER COLUMN queue SET DEFAULT '';
