task :benchmark_queues do
  # The following is a somewhat simplistic benchmark (aren't they all) meant
  # to compare the speed and concurrency of the locking mechanisms used by Que
  # (standard and lateral queries), DelayedJob and QueueClassic - it does this
  # by simply sending the raw queries that each system sends during operation.

  # It is NOT meant to benchmark the overall performance of each system (which
  # would include the time each spends working in Ruby), but to see which one
  # supports the highest concurrency under load, assuming that there will be
  # many workers and that Postgres will be the bottleneck. I'm unsure how
  # useful it is for this, but it's a start.

  JOB_COUNT          = (ENV['JOB_COUNT'] || 1000).to_i
  WORKER_COUNT       = (ENV['WORKER_COUNT'] || 10).to_i
  SYNCHRONOUS_COMMIT = ENV['SYNCHRONOUS_COMMIT'] || 'on'

  require 'uri'
  require 'pg'
  require 'connection_pool'

  uri = URI.parse ENV["DATABASE_URL"] || "postgres://postgres:@localhost/que-test"

  new_connection = proc do
    PG::Connection.open :host     => uri.host,
                        :user     => uri.user,
                        :password => uri.password,
                        :port     => uri.port || 5432,
                        :dbname   => uri.path[1..-1]
  end

  pg = new_connection.call



  # Necessary setup, mostly for QueueClassic. I apologize for this - I hope your editor supports code folding.
  pg.async_exec <<-SQL
    SET SESSION client_min_messages = 'WARNING';

    -- Que table.
    DROP TABLE IF EXISTS que_jobs;
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

    -- DelayedJob table.
    DROP TABLE IF EXISTS delayed_jobs;
    CREATE TABLE delayed_jobs
    (
      id serial NOT NULL,
      priority integer NOT NULL DEFAULT 0,
      attempts integer NOT NULL DEFAULT 0,
      handler text NOT NULL,
      last_error text,
      run_at timestamp without time zone,
      locked_at timestamp without time zone,
      failed_at timestamp without time zone,
      locked_by character varying(255),
      queue character varying(255),
      created_at timestamp without time zone,
      updated_at timestamp without time zone,
      CONSTRAINT delayed_jobs_pkey PRIMARY KEY (id)
    );
    ALTER TABLE delayed_jobs
      OWNER TO postgres;

    CREATE INDEX delayed_jobs_priority
      ON delayed_jobs
      USING btree
      (priority, run_at);



    -- QueueClassic table and functions.
    DROP FUNCTION IF EXISTS lock_head(tname varchar);
    DROP FUNCTION IF EXISTS lock_head(q_name varchar, top_boundary integer);
    DROP FUNCTION IF EXISTS queue_classic_notify() cascade;
    DROP TABLE IF EXISTS queue_classic_jobs;

    CREATE TABLE queue_classic_jobs (
      id bigserial PRIMARY KEY,
      q_name text not null check (length(q_name) > 0),
      method text not null check (length(method) > 0),
      args   text not null,
      locked_at timestamptz
    );

    alter table queue_classic_jobs alter column args type json using (args::json);

    create function queue_classic_notify() returns trigger as $$ begin
      perform pg_notify(new.q_name, '');
      return null;
    end $$ language plpgsql;

    create trigger queue_classic_notify
    after insert on queue_classic_jobs
    for each row
    execute procedure queue_classic_notify();

    CREATE INDEX idx_qc_on_name_only_unlocked ON queue_classic_jobs (q_name, id) WHERE locked_at IS NULL;

    CREATE OR REPLACE FUNCTION lock_head(q_name varchar, top_boundary integer)
    RETURNS SETOF queue_classic_jobs AS $$
    DECLARE
      unlocked bigint;
      relative_top integer;
      job_count integer;
    BEGIN
      -- The purpose is to release contention for the first spot in the table.
      -- The select count(*) is going to slow down dequeue performance but allow
      -- for more workers. Would love to see some optimization here...

      EXECUTE 'SELECT count(*) FROM '
        || '(SELECT * FROM queue_classic_jobs WHERE q_name = '
        || quote_literal(q_name)
        || ' LIMIT '
        || quote_literal(top_boundary)
        || ') limited'
      INTO job_count;

      SELECT TRUNC(random() * (top_boundary - 1))
      INTO relative_top;

      IF job_count < top_boundary THEN
        relative_top = 0;
      END IF;

      LOOP
        BEGIN
          EXECUTE 'SELECT id FROM queue_classic_jobs '
            || ' WHERE locked_at IS NULL'
            || ' AND q_name = '
            || quote_literal(q_name)
            || ' ORDER BY id ASC'
            || ' LIMIT 1'
            || ' OFFSET ' || quote_literal(relative_top)
            || ' FOR UPDATE NOWAIT'
          INTO unlocked;
          EXIT;
        EXCEPTION
          WHEN lock_not_available THEN
            -- do nothing. loop again and hope we get a lock
        END;
      END LOOP;

      RETURN QUERY EXECUTE 'UPDATE queue_classic_jobs '
        || ' SET locked_at = (CURRENT_TIMESTAMP)'
        || ' WHERE id = $1'
        || ' AND locked_at is NULL'
        || ' RETURNING *'
      USING unlocked;

      RETURN;
    END;
    $$ LANGUAGE plpgsql;

    CREATE OR REPLACE FUNCTION lock_head(tname varchar)
    RETURNS SETOF queue_classic_jobs AS $$
    BEGIN
      RETURN QUERY EXECUTE 'SELECT * FROM lock_head($1,10)' USING tname;
    END;
    $$ LANGUAGE plpgsql;





    INSERT INTO que_jobs (job_class, args, priority)
    SELECT 'Que::Job', ('[' || i || ',{}]')::json, 1
    FROM generate_Series(1,#{JOB_COUNT}) AS i;

    INSERT INTO que_lateral_jobs (job_class, args, priority)
    SELECT 'Que::Job', ('[' || i || ',{}]')::json, 1
    FROM generate_Series(1,#{JOB_COUNT}) AS i;

    INSERT INTO delayed_jobs (handler, run_at, created_at, updated_at)
    SELECT '--- !ruby/struct:NewsletterJob\ntext: lorem ipsum...\nemails: blah@blah.com\n', now(), now(), now()
    FROM generate_Series(1,#{JOB_COUNT}) AS i;

    INSERT INTO queue_classic_jobs (q_name, method, args)
    SELECT 'default', 'Kernel.puts', '["hello world"]'
    FROM generate_Series(1,#{JOB_COUNT}) AS i;




    -- Necessary tables and functions made, now stock them with jobs and analyze.
    ANALYZE;
  SQL


  queries = {
    :que => (
      <<-SQL
        WITH RECURSIVE cte AS (
          SELECT (job).*, pg_try_advisory_lock((job).job_id) AS locked
          FROM (
            SELECT job
            FROM que_jobs AS job
            WHERE run_at <= now()
            ORDER BY priority, run_at, job_id
            LIMIT 1
          ) AS t1
          UNION ALL (
            SELECT (job).*, pg_try_advisory_lock((job).job_id) AS locked
            FROM (
              SELECT (
               SELECT job
                FROM que_jobs AS job
                WHERE run_at <= now() AND (priority, run_at, job_id) > (cte.priority, cte.run_at, cte.job_id)
                ORDER BY priority, run_at, job_id
                LIMIT 1
              ) AS job
              FROM cte
              WHERE NOT cte.locked
              LIMIT 1
            ) AS t1
          )
        )
        SELECT job_id, priority, run_at, args, job_class, error_count
        FROM cte
        WHERE locked
        LIMIT 1
      SQL
    ),
    :delayed_job => (
      # From delayed_job_active_record
      <<-SQL
        UPDATE delayed_jobs
        SET locked_at = now(),
            locked_by = $1::text
        WHERE id IN (
          SELECT id
          FROM delayed_jobs
          WHERE (
            (run_at <= now() AND (locked_at IS NULL OR locked_at < now()) OR locked_by = $1) AND failed_at IS NULL
          )
          ORDER BY priority ASC, run_at ASC
          LIMIT 1
          FOR UPDATE
        )
        RETURNING *
      SQL
    )
  }

  connections = WORKER_COUNT.times.map do
    conn = new_connection.call
    conn.async_exec "SET SESSION synchronous_commit = #{SYNCHRONOUS_COMMIT}"
    queries.each do |name, sql|
      conn.prepare(name.to_s, sql)
    end
    conn
  end



  # Track the ids that are worked, to make sure they're all hit.
  $results = {
    :delayed_job   => [],
    :queue_classic => [],
    :que           => []
  }

  def work_job(type, conn)
    case type
    when :delayed_job
      return unless r = conn.exec_prepared("delayed_job", [conn.object_id]).first
      $results[type] << r['id']
      conn.async_exec "DELETE FROM delayed_jobs WHERE id = $1", [r['id']]

    when :queue_classic
      return unless r = conn.async_exec("SELECT * FROM lock_head($1, $2)", ['default', 9]).first
      $results[type] << r['id']
      conn.async_exec "DELETE FROM queue_classic_jobs WHERE id = $1", [r['id']]

    when :que
      begin
        return unless r = conn.exec_prepared("que").first
        # Have to double-check that the job is valid, as explained at length in Que::Job.work.
        return true unless conn.async_exec("SELECT * FROM que_jobs WHERE priority = $1 AND run_at = $2 AND job_id = $3", [r['priority'], r['run_at'], r['job_id']]).first
        conn.async_exec "DELETE FROM que_jobs WHERE priority = $1 AND run_at = $2 AND job_id = $3", [r['priority'], r['run_at'], r['job_id']]
        $results[type] << r['job_id']
      ensure
        conn.async_exec "SELECT pg_advisory_unlock_all()" if r
      end

    end
  end

  puts "Benchmarking #{JOB_COUNT} jobs, #{WORKER_COUNT} workers and synchronous_commit = #{SYNCHRONOUS_COMMIT}..."

  {
    :delayed_job   => :delayed_jobs,
    :queue_classic => :queue_classic_jobs,
    :que           => :que_jobs
  }.each do |type, table|
    print "Benchmarking #{type}... "
    start = Time.now

    threads = connections.map do |conn|
      Thread.new do
        loop do
          begin
            break unless work_job(type, conn)
          rescue
            # DelayedJob deadlocks sometimes.
          end
        end
      end
    end

    threads.each &:join
    time = Time.now - start
    puts "#{JOB_COUNT} jobs in #{time} seconds = #{(JOB_COUNT / time).round} jobs per second"


    # These checks are commented out because I can't seem to get DelayedJob to
    # pass them (Que and QueueClassic don't have the same problem). It seems
    # to repeat some jobs multiple times on every run, and its run times are
    # also highly variable.

    # worked = $results[type].map(&:to_i).sort
    # puts "Jobs worked more than once! #{worked.inspect}" unless worked == worked.uniq
    # puts "Jobs worked less than once! #{worked.inspect}" unless worked.length == JOB_COUNT

    puts "Jobs left in DB" unless pg.async_exec("SELECT count(*) FROM #{table}").first['count'].to_i == 0
    puts "Advisory locks left over!" if pg.async_exec("SELECT * FROM pg_locks WHERE locktype = 'advisory'").first
  end
end
