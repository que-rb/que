ALTER TABLE que_jobs
  RENAME COLUMN job_id TO id;

ALTER TABLE que_jobs
  DROP CONSTRAINT que_jobs_pkey,
  ADD COLUMN is_processed BOOLEAN,
  ADD COLUMN data JSONB,
  ADD CONSTRAINT que_jobs_pkey PRIMARY KEY (id),
  ADD CONSTRAINT queue_length CHECK (char_length(queue) <= 60);

UPDATE que_jobs
SET is_processed = false,
    data = json_build_object('args', args::jsonb);

ALTER TABLE que_jobs
  ALTER COLUMN is_processed SET DEFAULT false,
  ALTER COLUMN is_processed SET NOT NULL,
  ALTER COLUMN data SET DEFAULT '{}',
  ALTER COLUMN data SET NOT NULL;

CREATE UNIQUE INDEX que_jobs_poll_idx
  ON que_jobs (queue, priority, run_at, id)
  WHERE NOT (is_processed);

CREATE INDEX que_jobs_data_gin_idx ON que_jobs USING gin (data jsonb_path_ops);

CREATE UNLOGGED TABLE que_lockers (
  pid           integer NOT NULL CONSTRAINT que_lockers_pkey PRIMARY KEY,
  worker_count  integer NOT NULL,
  ruby_pid      integer NOT NULL,
  ruby_hostname text    NOT NULL,
  queues        text[]  NOT NULL,
  listening     boolean NOT NULL,

  CONSTRAINT valid_queues CHECK (
    (array_ndims(queues) = 1) AND (array_length(queues, 1) >= 1)
  )
);

CREATE FUNCTION que_job_notify() RETURNS trigger AS $$
  DECLARE
    locker_pid integer;
    sort_key json;
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
          WHERE listening AND queues @> ARRAY[NEW.queue]
          ORDER BY md5(pid::text || id::text)
        ) t1
      ) t2
    ) t3
    WHERE NEW.id % count = row_number;

    IF locker_pid IS NOT NULL THEN
      -- There's a size limit to what can be broadcast via LISTEN/NOTIFY, so
      -- rather than throw errors when someone enqueues a big job, just
      -- broadcast the sort key, and let the locker query for the record. The
      -- worker will have to hit the DB in order to make sure the job is still
      -- visible anyway.
      SELECT row_to_json(t)
      INTO sort_key
      FROM (
        SELECT NEW.priority AS priority,
               NEW.run_at   AS run_at,
               NEW.id       AS id
      ) t;

      PERFORM pg_notify('que_locker_' || locker_pid::text, sort_key::text);
    END IF;

    RETURN null;
  END
$$
LANGUAGE plpgsql;

CREATE TRIGGER que_job_notify
  AFTER INSERT ON que_jobs
  FOR EACH ROW
  EXECUTE PROCEDURE que_job_notify();
