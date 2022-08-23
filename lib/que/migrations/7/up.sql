DROP TRIGGER que_job_notify ON que_jobs;
CREATE TRIGGER que_job_notify
  AFTER INSERT ON que_jobs
  FOR EACH ROW
  WHEN (NOT coalesce(current_setting('que.skip_notify', true), '') = 'true')
  EXECUTE PROCEDURE public.que_job_notify();

DROP TRIGGER que_state_notify ON que_jobs;
CREATE TRIGGER que_state_notify
  AFTER INSERT OR UPDATE OR DELETE ON que_jobs
  FOR EACH ROW
  WHEN (NOT coalesce(current_setting('que.skip_notify', true), '') = 'true')
  EXECUTE PROCEDURE public.que_state_notify();
