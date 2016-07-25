ALTER TABLE que_jobs
  DROP CONSTRAINT que_jobs_pkey,
  DROP COLUMN queue,
  ADD CONSTRAINT que_jobs_pkey PRIMARY KEY (priority, run_at, job_id);

CREATE UNLOGGED TABLE que_lockers (
  pid           integer NOT NULL CONSTRAINT que_lockers_pkey PRIMARY KEY,
  worker_count  integer NOT NULL,
  ruby_pid      integer NOT NULL,
  ruby_hostname text    NOT NULL,
  listening     boolean NOT NULL
);

CREATE FUNCTION que_job_notify() RETURNS trigger AS $$
  DECLARE
    locker_pid  integer;
    primary_key json;
  BEGIN
    -- Don't do anything if the job is scheduled for a future time.
    IF NEW.run_at IS NOT NULL AND NEW.run_at > now() THEN
      RETURN null;
    END IF;

    -- Pick a locker to notify of the job's insertion, weighted by their
    -- number of workers. Should bounce semi-randomly between lockers on each
    -- invocation, hence the md5-ordering, but still touch each one equally,
    -- hence the modulo using the job_id. This could probably be written a lot
    -- more efficiently, but it runs plenty fast for now, and is easily
    -- changeable later.
    SELECT pid
    INTO locker_pid
    FROM (
      SELECT *, last_value(row_number) OVER () + 1 AS count
      FROM (
        SELECT *, row_number() OVER () - 1 AS row_number
        FROM (
          SELECT *
          FROM public.que_lockers ql, generate_series(1, ql.worker_count) AS id
          WHERE listening
          ORDER BY md5(pid::text || id::text)
        ) t1
      ) t2
    ) t3
    WHERE NEW.job_id % count = row_number;

    IF locker_pid IS NOT NULL THEN
      -- There's a size limit to what can be broadcast via LISTEN/NOTIFY, so
      -- rather than throw errors when someone enqueues a big job, just
      -- broadcast the primary key and let the locker query for the record.
      -- The locker will have to hit the DB in order to lock the job anyway.
      SELECT row_to_json(t)
      INTO primary_key
      FROM (
        SELECT NEW.priority AS priority,
               NEW.run_at   AS run_at,
               NEW.job_id   AS job_id
      ) t;

      PERFORM pg_notify('que_locker_' || locker_pid::text, primary_key::text);
    END IF;

    RETURN null;
  END
$$
LANGUAGE plpgsql;

CREATE TRIGGER que_job_notify
  AFTER INSERT ON que_jobs
  FOR EACH ROW
  EXECUTE PROCEDURE que_job_notify();
