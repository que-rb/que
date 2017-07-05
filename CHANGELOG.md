### 0.13.1 (2017-07-05)

*   Fix issue that caused error stacktraces to not be persisted in most cases.

### 0.13.0 (2017-06-08)

*   Fix recurring JSON issues by dropping MultiJson support. Previously MultiJson was detected and used automatically, and now it's just ignored and stdlib JSON used instead, so this shouldn't require any code changes.

### 0.12.3 (2017-06-01)

*   Fix incompatibility with MultiJson introduced by the previous release.

### 0.12.2 (2017-06-01)

*   Fix security vulnerability in parsing JSON from the DB (by specifying create_additions: false). This shouldn't be a concern unless you were passing untrusted user input in your job arguments. (hmac)

### 0.12.1 (2017-01-22)

*   Fix incompatibility with Rails 5.0. (#166) (nbibler, thedarkone)

### 0.12.0 (2016-09-09)

*   The error_handler configuration option has been renamed to error_notifier, which is more descriptive of what it's actually supposed to do. You can still use error_handler for configuration, but you'll get a warning.

*   Introduced a new framework for handling errors on a per-job basis. See the docs for more information. (#106, #147)

### 0.11.6 (2016-07-01)

*   Fix for operating in nested transactions in Rails 5.0. (#160) (greysteil)

### 0.11.5 (2016-05-13)

*   Fix error when running `que -v`. (#154) (hardbap)

### 0.11.4 (2016-03-03)

*   Fix incompatibility with ActiveRecord 5.0.0.beta3. (#143, #144) (joevandyk)

### 0.11.3 (2016-02-26)

*   Fixed bug with displaying the current version of the que executable. (#122) (hardbap)

*   Output to STDOUT when running via the executable or rake task is no longer buffered. This prevented logging in some cases. (#129) (hmarr)

*   Officially added support for Ruby 2.2 and 2.3.

*   String literals are now frozen on Ruby 2.3.

### 0.11.2 (2015-09-09)

*   Fix Job class constantizing when ActiveSupport isn't loaded. (#121) (godfat)

### 0.11.1 (2015-09-04)

*   The `rake que:work` rake task that was specific to Rails has been deprecated and will be removed in Que 1.0. A deprecation warning will display when it is run.

### 0.11.0 (2015-09-04)

*   A command-line program has been added that can be used to work jobs in a more flexible manner than the previous rake task. Run `que -h` for more information.

*   The worker pool will no longer start automatically in the same process when running the rails server - this behavior was too prone to breakage. If you'd like to recreate the old behavior, you can manually set `Que.mode = :async` in your app whenever conditions are appropriate (classes have loaded, a database connection has been established, and the process will not be forking).

*   Add a Que.disable_prepared_transactions= configuration option, to make it easier to use tools like pgbouncer. (#110)

*   Add a Que.json_converter= option, to configure how arguments are transformed before being passed to the job. By default this is set to the `Que::INDIFFERENTIATOR` proc, which provides simple indifferent access (via strings or symbols) to args hashes. If you're using Rails, the default is to convert the args to HashWithIndifferentAccess instead. You can also pass it the Que::SYMBOLIZER proc, which will destructively convert all keys in the args hash to symbols (this will probably be the default in Que 1.0). If you want to define a custom converter, you will usually want to pass this option a proc, and you'll probably want it to be recursive. See the implementations of Que::INDIFFERENTIATOR and Que::SYMBOLIZER for examples. (#113)

*   When using Que with ActiveRecord, workers now call `ActiveRecord::Base.clear_active_connections!` between jobs. This cleans up connections that ActiveRecord leaks when it is used to access mutliple databases. (#116)

*   If it exists, use String#constantize to constantize job classes, since ActiveSupport's constantize method behaves better with Rails' autoloading. (#115, #120) (joevandyk)

### 0.10.0 (2015-03-18)

*   When working jobs via the rake task, Rails applications are now eager-loaded if present, to avoid problems with multithreading and autoloading. (#96) (hmarr)

*   The que:work rake task now uses whatever logger Que is configured to use normally, rather than forcing the use of STDOUT. (#95)

*   Add Que.transaction() helper method, to aid in transaction management in migrations or when the user's ORM doesn't provide one. (#81)

### 0.9.2 (2015-02-05)

*   Fix a bug wherein the at_exit hook in the railtie wasn't waiting for jobs to finish before exiting.

*   Fix a bug wherein the que:work rake task wasn't waiting for jobs to finish before exiting. (#85) (tycooon)

### 0.9.1 (2015-01-11)

*   Use now() rather than 'now' when inserting jobs, to avoid using an old value as the default run_at in prepared statements. (#74) (bgentry)

### 0.9.0 (2014-12-16)

*   The error_handler callable is now passed two objects, the error and the job that raised it. If your current error_handler is a proc, as recommended in the docs, you shouldn't need to make any code changes, unless you want to use the job in your error handling. If your error_handler is a lambda, or another callable with a strict arity requirement, you'll want to change it before upgrading. (#69) (statianzo)

### 0.8.2 (2014-10-12)

*   Fix errors raised during rollbacks in the ActiveRecord adapter, which remained silent until Rails 4.2. (#64, #65) (Strech)

### 0.8.1 (2014-07-28)

*   Fix regression introduced in the `que:work` rake task by the `mode` / `worker_count` disentangling in 0.8.0. (#50)

### 0.8.0 (2014-07-12)

*   A callable can now be set as the logger, like `Que.logger = proc { MyLogger.new }`. Que uses this in its Railtie for cleaner initialization, but it is also available for public use.

*   `Que.mode=` and `Que.worker_count=` now function independently. That is, setting the worker_count to a nonzero number no longer sets mode = :async (triggering the pool to start working jobs), and setting it to zero no longer sets mode = :off. Similarly, setting the mode to :async no longer sets the worker_count to 4 from 0, and setting the mode to :off no longer sets the worker_count to 0. This behavior was changed because it was interfering with configuration during initialization of Rails applications, and because it was unexpected. (#47)

*   Fixed a similar bug wherein setting a wake_interval during application startup would break worker awakening after the process was forked.

### 0.7.3 (2014-05-19)

*   When mode = :sync, don't touch the database at all when running jobs inline. Needed for ActiveJob compatibility (#46).

### 0.7.2 (2014-05-18)

*   Fix issue wherein intermittent worker wakeups would not work after forking (#44).

### 0.7.1 (2014-04-29)

*   Fix errors with prepared statements when ActiveRecord reconnects to the database. (dvrensk)

*   Don't use prepared statements when inside a transaction. This negates the risk of a prepared statement error harming the entire transaction. The query that benefits the most from preparation is the job-lock CTE, which is never run in a transaction, so the performance impact should be negligible.

### 0.7.0 (2014-04-09)

*   `JobClass.queue(*args)` has been deprecated and will be removed in version 1.0.0. Please use `JobClass.enqueue(*args)` instead.

*   The `@default_priority` and `@default_run_at` variables have been deprecated and will be removed in version 1.0.0. Please use `@priority` and `@run_at` instead, respectively.

*   Log lines now include the process pid - its omission in the previous release was an oversight.

*   The [Pond gem](https://github.com/chanks/pond) is now supported as a connection. It is very similar to the ConnectionPool gem, but creates connections lazily and is dynamically resizable.

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
