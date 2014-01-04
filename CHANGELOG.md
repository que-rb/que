### Unreleased

*   When queueing a job, Que will wait until the current transaction commits and then wake a background worker, if possible. This allows newly queued jobs to be started immediately instead of waiting for a worker to wake up and poll, which may be up to `Que.sleep_period` seconds.

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
