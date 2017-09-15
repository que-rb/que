ALTER TABLE que_jobs RESET (fillfactor);

ALTER TABLE que_jobs DROP CONSTRAINT que_jobs_pkey;
DROP INDEX que_poll_idx;
DROP INDEX que_jobs_data_gin_idx;

DROP TRIGGER que_job_notify ON que_jobs;
DROP FUNCTION que_job_notify();
DROP TRIGGER que_state_notify ON que_jobs;
DROP FUNCTION que_state_notify();
DROP FUNCTION que_determine_job_state(que_jobs);
DROP TABLE que_lockers;

DROP TABLE que_values;

ALTER TABLE que_jobs RENAME COLUMN id TO job_id;
ALTER SEQUENCE que_jobs_id_seq RENAME TO que_jobs_job_id_seq;

ALTER TABLE que_jobs RENAME COLUMN last_error_message TO last_error;

ALTER TABLE que_jobs
  DROP CONSTRAINT error_length,
  DROP CONSTRAINT queue_length,
  DROP CONSTRAINT job_class_length,
  DROP COLUMN finished_at,
  ADD COLUMN args JSON;

UPDATE que_jobs
  SET args = (data->'args')::json,
  queue = CASE queue WHEN 'default' THEN '' ELSE queue END,
  last_error = last_error || coalesce(E'\n' || last_error_backtrace, '');

ALTER TABLE que_jobs
  DROP COLUMN data,
  DROP COLUMN last_error_backtrace,
  ALTER COLUMN args SET NOT NULL,
  ALTER COLUMN args SET DEFAULT '[]',
  ALTER COLUMN queue SET DEFAULT '';

ALTER TABLE que_jobs
  ADD PRIMARY KEY (queue, priority, run_at, job_id);

DROP FUNCTION que_validate_tags(jsonb);
