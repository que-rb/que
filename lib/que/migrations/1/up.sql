CREATE TABLE que_jobs
(
  priority    integer     NOT NULL DEFAULT 1,
  run_at      timestamptz NOT NULL DEFAULT now(),
  job_id      bigserial   NOT NULL,
  job_class   text        NOT NULL,
  args        json        NOT NULL DEFAULT '[]'::json,
  error_count integer     NOT NULL DEFAULT 0,
  last_error  text,

  CONSTRAINT que_jobs_pkey PRIMARY KEY (priority, run_at, job_id)
);
