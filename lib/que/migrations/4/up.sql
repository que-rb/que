ALTER TABLE que_jobs SET (
  fillfactor = 90,
  -- TODO: Try tweaking these values during benchmarking.
  autovacuum_vacuum_scale_factor = 0.1,
  autovacuum_vacuum_threshold = 50
);

ALTER TABLE que_jobs
  DROP CONSTRAINT que_jobs_pkey;

ALTER TABLE que_jobs
  RENAME COLUMN job_id TO id;

ALTER SEQUENCE que_jobs_job_id_seq RENAME TO que_jobs_id_seq;

ALTER TABLE que_jobs
  RENAME COLUMN last_error TO last_error_message;

ALTER TABLE que_jobs
  ADD COLUMN last_error_backtrace text,
  ADD COLUMN finished_at timestamptz,
  ADD COLUMN data JSONB;

UPDATE que_jobs
SET queue = CASE queue WHEN '' THEN 'default' ELSE queue END,
    -- Some old error fields are missing the backtrace, so try to provide a
    -- reasonable default.
    last_error_backtrace =
      CASE
      WHEN last_error_message IS NULL
        THEN NULL
      WHEN last_error_message ~ '\n'
        THEN left(regexp_replace(last_error_message, '^[^\n]+\n', ''), 10000)
      ELSE
        ''
      END,
    last_error_message = left(substring(last_error_message from '^[^\n]+'), 500),
    data = json_build_object(
      'args',
      (
        CASE json_typeof(args)
        WHEN 'array' THEN args
        ELSE json_build_array(args)
        END
      )
    )::jsonb;

ALTER TABLE que_jobs
  ALTER COLUMN queue SET DEFAULT 'default',
  ALTER COLUMN data SET DEFAULT '{"args":[]}',
  ALTER COLUMN data SET NOT NULL,
  DROP COLUMN args,
  ADD CONSTRAINT data_format CHECK (
    (jsonb_typeof(data) = 'object')
    AND
    ((data->'args') IS NOT NULL)
    AND
    (jsonb_typeof(data->'args') = 'array')
  ),
  ADD CONSTRAINT error_length CHECK (
    (char_length(last_error_message) <= 500) AND
    (char_length(last_error_backtrace) <= 10000)
  ),
  ADD PRIMARY KEY (id);

CREATE INDEX que_poll_idx ON que_jobs (queue, priority, run_at, id) WHERE finished_at IS NULL;

CREATE INDEX que_jobs_data_gin_idx ON que_jobs USING gin (data jsonb_path_ops);

CREATE UNLOGGED TABLE que_lockers (
  pid               integer NOT NULL CONSTRAINT que_lockers_pkey PRIMARY KEY,
  worker_count      integer NOT NULL,
  worker_priorities integer[] NOT NULL,
  ruby_pid          integer NOT NULL,
  ruby_hostname     text    NOT NULL,
  queues            text[]  NOT NULL,
  listening         boolean NOT NULL,

  CONSTRAINT valid_worker_priorities CHECK (
    (array_ndims(worker_priorities) = 1)
    AND
    (array_length(worker_priorities, 1) IS NOT NULL) -- Doesn't do zero.
  ),

  CONSTRAINT valid_queues CHECK (
    (array_ndims(queues) = 1)
    AND
    (array_length(queues, 1) IS NOT NULL) -- Doesn't do zero.
  )
);

CREATE INDEX que_lockers_listening_queues_idx
  ON que_lockers USING gin(queues) WHERE (listening);

CREATE FUNCTION que_job_notify() RETURNS trigger AS $$
  DECLARE
    locker_pid integer;
    sort_key json;
  BEGIN
    -- Don't do anything if the job is scheduled for a future time.
    IF NEW.run_at IS NOT NULL AND NEW.run_at > now() THEN
      RETURN null;
    END IF;

    -- Pick a locker to notify of the job's insertion, weighted by their number
    -- of workers. Should bounce pseudorandomly between lockers on each
    -- invocation, hence the md5-ordering, but still touch each one equally,
    -- hence the modulo using the job_id.
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
      -- broadcast the most pertinent information, and let the locker query for
      -- the record after it's taken the lock. The worker will have to hit the
      -- DB in order to make sure the job is still visible anyway.
      SELECT row_to_json(t)
      INTO sort_key
      FROM (
        SELECT
          'new_job'    AS message_type,
          NEW.queue    AS queue,
          NEW.priority AS priority,
          -- Make sure we output timestamps as UTC ISO 8601
          to_char(NEW.run_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS run_at,
          NEW.id       AS id
      ) t;

      PERFORM pg_notify('que_listener_' || locker_pid::text, sort_key::text);
    END IF;

    RETURN null;
  END
$$
LANGUAGE plpgsql;

CREATE TRIGGER que_job_notify
  AFTER INSERT ON que_jobs
  FOR EACH ROW
  EXECUTE PROCEDURE que_job_notify();
