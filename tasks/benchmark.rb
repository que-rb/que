task :benchmark do
  # The following benchmark is meant to test Que's scalability by having it
  # bombard Postgres from many, many processes. Note that this benchmark tests
  # the entire Que stack, not just the locking queries.

  JOB_COUNT          = (ENV['JOB_COUNT'] || 1000).to_i
  PROCESS_COUNT      = (ENV['PROCESS_COUNT'] || 1).to_i
  WORKER_COUNT       = (ENV['WORKER_COUNT']  || 4).to_i
  SYNCHRONOUS_COMMIT = ENV['SYNCHRONOUS_COMMIT'] || 'on'

  require 'que'
  require 'uri'
  require 'pg'
  require 'connection_pool'

  uri = URI.parse ENV["DATABASE_URL"] || "postgres://postgres:@localhost/que-test"

  new_connection = proc do
    conn = PG::Connection.open :host     => uri.host,
                               :user     => uri.user,
                               :password => uri.password,
                               :port     => uri.port || 5432,
                               :dbname   => uri.path[1..-1]

    conn.async_exec "SET SESSION synchronous_commit = #{SYNCHRONOUS_COMMIT}"
    conn
  end

  Que.connection = pg = new_connection.call
  Que.drop! rescue nil
  Que.create!

  # Stock table with jobs and analyze.
  pg.async_exec <<-SQL
    INSERT INTO que_jobs (job_class, args, priority)
    SELECT 'Que::Job', ('[' || i || ',{}]')::json, 1
    FROM generate_Series(1,#{JOB_COUNT}) AS i;
    ANALYZE;
  SQL

  # Fork!
  $parent_pid = Process.pid
  def parent?
    Process.pid == $parent_pid
  end

  # Synchronize all workers to start at the same time using, what else?
  # Advisory locks. I am such a one-trick pony.
  pg.async_exec("SELECT pg_advisory_lock(0)")

  PROCESS_COUNT.times { Process.fork if parent? }

  if parent?
    # This is the main process, get ready to start monitoring the queues.

    # First hold until all the children are ready.
    sleep 0.1 until pg.async_exec("select count(*) from pg_locks where locktype = 'advisory' and objid = 0").first['count'].to_i == PROCESS_COUNT + 1

    puts "Benchmarking: #{JOB_COUNT} jobs, #{PROCESS_COUNT} processes with #{WORKER_COUNT} workers each, synchronous_commit = #{SYNCHRONOUS_COMMIT}..."
    pg.async_exec("select pg_advisory_unlock_all()") # Go!
    start = Time.now

    loop do
      sleep 0.01
      break if pg.async_exec("SELECT 1 AS one FROM que_jobs LIMIT 1").none? # There must be a better way to do this?
    end
    time = Time.now - start

    locks = pg.async_exec("SELECT * FROM pg_locks WHERE locktype = 'advisory'").to_a
    puts "Advisory locks left over! #{locks.inspect}" if locks.any?
    puts "#{JOB_COUNT} jobs in #{time} seconds = #{(JOB_COUNT / time).round} jobs per second"
  else
    # This is a child, get ready to start hitting the queues.
    pool = ConnectionPool.new :size => WORKER_COUNT, &new_connection

    Que.connection = pool

    pool.with do |conn|
      # Block here until the advisory lock is released, which is our start pistol.
      conn.async_exec "SELECT pg_advisory_lock(0); SELECT pg_advisory_unlock_all();"
    end

    Que.mode = :async
    Que.worker_count = WORKER_COUNT

    loop do
      sleep 1
      break if pool.with { |pg| pg.async_exec("SELECT 1 AS one FROM que_jobs LIMIT 1").none? }
    end
  end

  Process.waitall
end
