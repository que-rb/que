DROP TRIGGER que_job_notify ON que_jobs;
CREATE TRIGGER que_job_notify
  AFTER INSERT ON que_jobs
  FOR EACH ROW
  EXECUTE PROCEDURE public.que_job_notify();
