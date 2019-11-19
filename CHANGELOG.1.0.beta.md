### 1.0.0.beta3 (2018-05-18)

*   Added support for customizing log levels for `job_worked` events (#217).

*   Began logging all `job_errored` events at the `ERROR` log level.

*   Fixed the Railtie when running in test mode (#214).

*   Tweaked the meanings of worker-priorities and worker-count options in the CLI, to better support use cases with low worker counts (#216).

### 1.0.0.beta2 (2018-04-13)

*   Fixed an incompatibility that caused the new locker to hang when using Rails in development mode (#213).

*   Fixed a bug with setting the log level via the CLI when the configured logger was based on a callable (#210).

*   Renamed Que.middleware to Que.job_middleware.

*   Added Que.sql_middleware.

*   Officially added support for Ruby 2.5.

*   Internal cleanup and renamings.

### 1.0.0.beta (2017-10-25)

*   **A schema upgrade to version 4 will be required for this release.** See [the migration doc](https://github.com/que-rb/que/blob/master/docs/migrating.md) for information if you're upgrading from a previous release.

    *   Please note that this migration requires a rewrite of the jobs table, which makes it O(n) with the size of the table. If you have a very large backlog of jobs you may want to schedule downtime for this migration.

*   Que's implementation has been changed from one in which worker threads hold their own PG connections and lock their own jobs to one in which a single thread (and PG connection) locks jobs through LISTEN/NOTIFY and batch polling, and passes jobs along to worker threads. This has many benefits, including:

    *   Jobs queued for immediate processing can be actively distributed to workers with LISTEN/NOTIFY, which is more efficient than having workers repeatedly poll for new jobs.

    *   When polling is necessary (to pick up jobs that are scheduled for the future or that need to be retried due to errors), jobs can be locked and fetched in batches, rather than one at a time.

    *   Individual workers no longer need to monopolize their own (usually idle) connections while working jobs, so Ruby processes will require fewer Postgres connections.

    *   PgBouncer or another external connection pool can be used for workers' connections (though not for the connection used to lock and listen for jobs).

*   Other features introduced in this version include:

    *   Much better support for all versions of ActiveJob.

        *   In particular, you may (optionally) include `Que::ActiveJob::JobExtensions` into `ApplicationJob` to get support for all of Que's job helper methods.

    *   Custom middleware that wrap running jobs are now supported.

    *   Support for categorizing jobs with tags.

    *   Support for configuring a `maximum_retry_count` on individual job classes.

    *   Job configuration options are now inheritable, so job class hierarchies are more useful.

    *   There are now built-in models for ActiveRecord and Sequel to allow inspecting the queue easily.

    *   Jobs that have finished working may optionally be retained in the database indefinitely.

        *   To keep a job record, replace the `destroy` calls in your jobs with `finish`. `destroy` will still delete records entirely, for jobs that you don't want to keep.

        *   If you don't resolve a job yourself one way or another, Que will still `destroy` the job for you by default.

        *   Finished jobs have a timestamp set in the finished_at column.

    *   Jobs that have errored too many times will now be marked as expired, and won't be retried again.

        *   You can configure a maximum_retry_count in your job classes, to set the threshold at which a job will be marked expired. The default is 15.

        *   To manually mark a job as expired (and keep it in the database but not try to run it again) you can call `expire` helper in your job.

    *   You can now set job priority thresholds for individual workers, to ensure that there will always be space available for high-priority jobs.

    *   `Que.job_states` returns a list of locked jobs and the hostname/pid of the Ruby processes that have locked them.

    *   `Que.connection_proc=` has been added, to allow for the easy integration of custom connection pools.

*   In keeping with semantic versioning, the major version is being bumped since the new implementation requires some backwards-incompatible changes. These changes include:

    *   Support for MRI Rubies before 2.2 has been dropped.

    *   Support for Postgres versions before 9.5 has been dropped (JSONB and upsert support is required).

    *   JRuby support has been dropped. It will be reintroduced whenever the jruby-pg gem is production-ready.

    *   The `que:work` rake task has been removed. Use the `que` executable instead.

        *   Therefore, configuring workers using QUE_* environment variables is no longer supported. Please pass the appropriate options to the `que` executable instead.

    *   The `mode` setter has been removed.

        *   To run jobs synchronously when they are enqueued (the old `:sync` behavior) you can set `Que.run_synchronously = true`.

        *   To start up the worker pool (the old :async behavior) you should use the `que` executable to start up a worker process. There's no longer a supported API for running workers outside of the `que` executable.

    *   The following methods are not meaningful under the new implementation and have been removed:

        *   The `Que.wake_interval` getter and setter.

        *   The `Que.worker_count` getter and setter.

        *   `Que.wake!`

        *   `Que.wake_all!`

    *   Since Que needs a dedicated Postgres connection to manage job locks, running Que through a single PG connection is no longer supported.

        *   It's not clear that anyone ever actually did this.

    *   `Que.worker_states` has been removed, as the connection that locks a job is no longer the one that the job is using to run. Its functionality has been partially replaced with `Que.job_states`.

    *   When using Rails, for simplicity, job attributes and keys in argument hashes are now converted to symbols when retrieved from the database, rather than being converted to instances of HashWithIndifferentAccess.

    *   Arguments passed to jobs are now deep-frozen, to prevent unexpected behavior when the args are mutated and the job is reenqueued.

    *   Since JSONB is now used to store arguments, the order of argument hashes is no longer maintained.

        *   It wouldn't have been a good idea to rely on this anyway.

    *   Calling Que.log() directly is no longer supported/recommended.

    *   Features marked as deprecated in the final 0.x releases have been removed.

*   Finally, if you've built up your own tooling and customizations around Que, you may need to be aware of some DB schema changes made in the migration to schema version #4.

    *   The `job_id` column has been renamed `id` and is now the primary key. This makes it easier to manage the queue using an ActiveRecord model.

    *   Finished jobs are now kept in the DB, unless you explicitly call `destroy`. If you want to query the DB for only jobs that haven't finished yet, add a `WHERE finished_at IS NULL` condition to your query, or use the not_finished scope on one of the provided ORM models.

    *   There is now an `expired_at` timestamp column, which is set when a job reaches its maximum number of retries and will not be attempted again.

    *   Due to popular demand, the default queue name is now "default" rather than an empty string. The migration will move pending jobs under the "" queue to the "default" queue.

    *   The `last_error` column has been split in two, to `last_error_message` and `last_error_backtrace`. These two columns are now limited to 500 and 10,000 characters, respectively. The migration will split old error data correctly, and truncate it if necessary.

    *   Names for queues and job classes are now limited to 500 characters, which is still far longer than either of these values should reasonably be.

    *   There is now a `data` JSONB column which is used to support various ways of organizing jobs (setting tags on them, etc).
