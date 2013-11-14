CREATE TABLE que_jobs
(
  priority integer     NOT NULL DEFAULT 1,
  run_at   timestamptz NOT NULL DEFAULT now(),
  job_id   bigserial   NOT NULL,
  type     text        NOT NULL,
  args     json        NOT NULL DEFAULT '[]'::json,

  CONSTRAINT jobs_pkey PRIMARY KEY (priority, run_at, job_id)
);
