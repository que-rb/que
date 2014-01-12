-- 1 was a bad default. Starting from there, you couldn't tweak some jobs to
-- be more important without going into negative priorities, which is weird.
ALTER TABLE que_jobs ALTER COLUMN priority SET DEFAULT 100;
