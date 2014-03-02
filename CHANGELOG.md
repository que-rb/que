### Unreleased

*   **A schema upgrade to version 4 will be required for the next release.** See [the migration doc](https://github.com/chanks/que/blob/master/docs/migrating.md) for information if you're upgrading from a previous release.

*   Que's implementation has been changed from one in which worker threads hold their own PG connections and lock their own jobs to one in which a single thread and PG connection locks jobs through LISTEN/NOTIFY and batch polling, and passes jobs along to worker threads. This has many benefits, including:

    *   Individual workers no longer need to monopolize their own (possibly idle) connections while working jobs, so each Ruby process may require many fewer Postgres connections. It should also allow for better use of PgBouncer.

    *   Jobs queued for immediate processing can be distributed to workers with LISTEN/NOTIFY, which is more efficient than constantly polling for new jobs.

    *   When polling is necessary (to pick up jobs that are scheduled for the future or that need to be retried due to errors), jobs can be locked in batches, rather than one at a time.

*   In keeping with semantic versioning, the next release will bump the version to 1.0.0, since the new implementation requires some backwards-incompatible changes. These changes include:

    *   `Que.connection=` has been removed. Instead, use `Que.connection_proc=` to hook Que into your connection pool directly. See the documentation for details.

    *   `Que.wake_interval`, `Que.wake_interval=`, `Que.wake!` and `Que.wake_all!` have no meaning under the new implementation, and so have been removed.

    *   It is no longer possible to run Que through a single PG connection. A connection pool with a size of at least 2 is required.

    *   It is no longer possible to inspect the Postgres connection that is working each job. So, `Que.worker_states` has been removed. Its functionality has been partially replaced with `Que.job_states`, which returns list of locked jobs and the hostname/pid of the Ruby processes that have locked them.

### 0.6.0 (2014-02-04)

*   **A schema upgrade to version 3 is required for this release.** See [the migration doc](https://github.com/chanks/que/blob/master/docs/migrating.md) for information if you're upgrading from a previous release.

*   You can now run a job's logic directly (without enqueueing it) like `MyJob.run(arg1, arg2, :other_arg => arg3)`. This is useful when a job class encapsulates logic that you want to invoke without involving the entire queue.

*   You can now check the current version of Que's database schema with `Que.db_version`.

*   The method for enqueuing a job has been renamed from `MyJob.queue` to `MyJob.enqueue`, since we were beginning to use the word 'queue' in a LOT of places. `MyJob.queue` still works, but it may be removed at some point.

*   The variables for setting the defaults for a given job class have been changed from `@default_priority` to `@priority` and `@default_run_at` to `@run_at`. The old variables still work, but like `Job.queue`, they may be removed at some point.

*   Log lines now include the machine's hostname, since a pid alone may not uniquely identify a process.

*   Multiple queues are now supported. See [the docs](https://github.com/chanks/que/blob/master/docs/multiple_queues.md) for details. (chanks, joevandyk)

*   Rubinius 2.2 is now supported. (brixen)

*   Job classes may now define their own logic for determining the retry interval when a job raises an error. See [error handling](https://github.com/chanks/que/blob/master/docs/error_handling.md) for more information.

### 0.5.0 (2014-01-14)

*   When running a worker pool inside your web process on ActiveRecord, Que will now wake a worker once a transaction containing a queued job is committed. (joevandyk, chanks)

*   The `que:work` rake task now has a default wake_interval of 0.1 seconds, since it relies exclusively on polling to pick up jobs. You can set a QUE_WAKE_INTERVAL environment variable to change this. The environment variable to set a size for the worker pool in the rake task has also been changed from WORKER_COUNT to QUE_WORKER_COUNT.

*   Officially support Ruby 1.9.3. Note that due to the Thread#kill problems (see "Remove Que.stop!" below) there's a danger of data corruption when running under 1.9, though.

*   The default priority for jobs is now 100 (it was 1 before). Like always (and like delayed_job), a lower priority means it's more important. You can migrate the schema version to 2 to set the new default value on the que_jobs table, though it's only necessary if you're doing your own INSERTs - if you use `MyJob.queue`, it's already taken care of.

*   Added a migration system to make it easier to change the schema when updating Que. You can now write, for example, `Que.migrate!(:version => 2)` in your migrations. Migrations are run transactionally.

*   The logging format has changed to be more easily machine-readable. You can also now customize the logging format by assigning a callable to Que.log_formatter=. See the new doc on [logging](https://github.com/chanks/que/blob/master/docs/logging.md)) for details. The default logger level is INFO - for less critical information (such as when no jobs were found to be available or when a job-lock race condition has been detected and avoided) you can set the QUE_LOG_LEVEL environment variable to DEBUG.

*   MultiJson is now a soft dependency. Que will use it if it is available, but it is not required.

*   Remove Que.stop!.

    Using Thread#raise to kill workers is a bad idea - the results are unpredictable and nearly impossible to spec reliably. Its purpose was to prevent premature commits in ActiveRecord/Sequel when a thread is killed during shutdown, but it's possible to detect that situation on Ruby 2.0+, so this is really better handled by the ORMs directly. See the pull requests for [Sequel](https://github.com/jeremyevans/sequel/pull/752) and [ActiveRecord](https://github.com/rails/rails/pull/13656).

    Now, when a process exits, if the worker pool is running (whether in a rake task or in a web process) the exit will be stalled until all workers have finished their current jobs. If you have long-running jobs, this may take a long time. If you need the process to exit immediately, you can SIGKILL without any threat of commiting prematurely.

### 0.4.0 (2014-01-05)

*   Que.wake_all! was added, as a simple way to wake up all workers in the pool.

*   Que.sleep_period was renamed to the more descriptive Que.wake_interval.

*   When queueing a job, Que will wait until the current transaction commits and then wake a background worker, if possible. This allows newly queued jobs to be started immediately instead of waiting for a worker to wake up and poll, which may be up to `Que.wake_interval` seconds.

    This feature currently only works with Sequel, since there doesn't seem to be a clean way to do it on ActiveRecord (if anyone can figure one out, please let me know). Note that if you're using ActiveRecord, you can always manually trigger a single worker to wake up and check for work by manually calling Que.wake! after your transaction completes.

*   Add Que.job_stats, which queries the database and returns statistics on the different job classes - for each class, how many are queued, how many are currently being worked, what is the highest error_count, and so on.

*   Add Que.worker_states, which queries the database and returns all currently-locked jobs and info on their workers' connections - what and when was the last query they ran, are they waiting on locks, and so on.

*   Have Que only clear advisory locks that it has taken when locking jobs, and not touch any that may have been taken by other code using the same connection.

*   Add Que.worker_count, to retrieve the current number of workers in the pool of the current process.

*   Much more internal cleanup.

### 0.3.0 (2013-12-21)

*   Add Que.stop!, which immediately kills all jobs being worked in the process.

    This can leave database connections and such in an unpredictable state, and so should only be used when the process is exiting.

*   Use Que.stop! to safely handle processes that exit while Que is running.

    Previously, a job that was in the middle of a transaction when the process was killed with SIGINT or SIGTERM would have had its work committed prematurely.

*   Clean up internals and hammer out several race conditions.

### 0.2.0 (2013-11-30)

*   Officially support JRuby 1.7.5+. Earlier versions may work.

    JRuby support requires the use of the `jruby-pg` gem, though that gem seems to currently be incompatible with ActiveRecord, so the ActiveRecord adapter specs don't pass (or even run). It works fine with Sequel and the other adapters, though.

*   Officially support Rubinius 2.1.1+. Earlier versions may work.

*   Use `multi_json` so we always use the fastest JSON parser available. (BukhariH)

*   :sync mode now ignores scheduled jobs (jobs queued with a specific run_at).

### 0.1.0 (2013-11-18)

*   Initial public release, after a test-driven rewrite.

    Officially support Ruby 2.0.0 and Postgres 9.2+.

    Also support ActiveRecord and bare PG::Connections, in or out of a ConnectionPool.

    Added a Railtie for easier setup with Rails, as well as a migration generator.

### 0.0.1 (2013-11-07)

*   Copy-pasted from an app of mine. Very Sequel-specific. Nobody look at it, let's pretend it never happened.
