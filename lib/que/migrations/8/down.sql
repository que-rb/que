DROP VIEW IF EXISTS public.que_jobs_ext;

ALTER TABLE que_jobs
  DROP COLUMN first_run_at;
