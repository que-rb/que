# Changelog

<!-- MarkdownTOC autolink=true -->

- [2.4.0 \(2024-08-21\)](#240-2024-08-21)
- [2.3.0 \(2023-10-16\)](#230-2023-10-16)
- [2.2.1 \(2023-04-28\)](#221-2023-04-28)
- [2.2.0 \(2022-08-29\)](#220-2022-08-29)
- [2.1.0 \(2022-08-25\)](#210-2022-08-25)
- [2.0.0 \(2022-08-25\)](#200-2022-08-25)
- [1.4.1 \(2022-07-24\)](#141-2022-07-24)
- [2.0.0.beta1 \(2022-03-24\)](#200beta1-2022-03-24)
- [1.4.0 \(2022-03-23\)](#140-2022-03-23)
- [1.3.1 \(2022-02-25\)](#131-2022-02-25)
- [1.3.0 \(2022-02-25\)](#130-2022-02-25)
- [1.2.0 \(2022-02-23\)](#120-2022-02-23)
- [1.1.0 \(2022-02-21\)](#110-2022-02-21)
- [1.0.0 \(2022-01-24\)](#100-2022-01-24)
- [1.0.0.beta5 \(2021-12-23\)](#100beta5-2021-12-23)
- [1.0.0.beta4 \(2020-01-17\)](#100beta4-2020-01-17)
- [1.0.0.beta3 \(2018-05-18\)](#100beta3-2018-05-18)
- [1.0.0.beta2 \(2018-04-13\)](#100beta2-2018-04-13)
- [1.0.0.beta \(2017-10-25\)](#100beta-2017-10-25)
- [0.14.3 \(2018-03-02\)](#0143-2018-03-02)
- [0.14.2 \(2018-01-05\)](#0142-2018-01-05)
- [0.14.1 \(2017-12-14\)](#0141-2017-12-14)
- [0.14.0 \(2017-08-11\)](#0140-2017-08-11)
- [0.13.1 \(2017-07-05\)](#0131-2017-07-05)
- [0.13.0 \(2017-06-08\)](#0130-2017-06-08)
- [0.12.3 \(2017-06-01\)](#0123-2017-06-01)
- [0.12.2 \(2017-06-01\)](#0122-2017-06-01)
- [0.12.1 \(2017-01-22\)](#0121-2017-01-22)
- [0.12.0 \(2016-09-09\)](#0120-2016-09-09)
- [0.11.6 \(2016-07-01\)](#0116-2016-07-01)
- [0.11.5 \(2016-05-13\)](#0115-2016-05-13)
- [0.11.4 \(2016-03-03\)](#0114-2016-03-03)
- [0.11.3 \(2016-02-26\)](#0113-2016-02-26)
- [0.11.2 \(2015-09-09\)](#0112-2015-09-09)
- [0.11.1 \(2015-09-04\)](#0111-2015-09-04)
- [0.11.0 \(2015-09-04\)](#0110-2015-09-04)
- [0.10.0 \(2015-03-18\)](#0100-2015-03-18)
- [0.9.2 \(2015-02-05\)](#092-2015-02-05)
- [0.9.1 \(2015-01-11\)](#091-2015-01-11)
- [0.9.0 \(2014-12-16\)](#090-2014-12-16)
- [0.8.2 \(2014-10-12\)](#082-2014-10-12)
- [0.8.1 \(2014-07-28\)](#081-2014-07-28)
- [0.8.0 \(2014-07-12\)](#080-2014-07-12)
- [0.7.3 \(2014-05-19\)](#073-2014-05-19)
- [0.7.2 \(2014-05-18\)](#072-2014-05-18)
- [0.7.1 \(2014-04-29\)](#071-2014-04-29)
- [0.7.0 \(2014-04-09\)](#070-2014-04-09)
- [0.6.0 \(2014-02-04\)](#060-2014-02-04)
- [0.5.0 \(2014-01-14\)](#050-2014-01-14)
- [0.4.0 \(2014-01-05\)](#040-2014-01-05)
- [0.3.0 \(2013-12-21\)](#030-2013-12-21)
- [0.2.0 \(2013-11-30\)](#020-2013-11-30)
- [0.1.0 \(2013-11-18\)](#010-2013-11-18)
- [0.0.1 \(2013-11-07\)](#001-2013-11-07)

<!-- /MarkdownTOC -->

## 2.4.0 (2024-08-21)

- **Fixed**:
    + Fixed `Que.server?` method returning the inverse of what was intended. This method can be used to determine whether Que is running as a server process (run from the Que CLI). [#426](https://github.com/que-rb/que/pull/426), context in [#382](https://github.com/que-rb/que/pull/382)
- **Added**:
    + Added logging of full job details rather than just `job_id`. Note that the hash `Que.log_formatter` is called with no longer contains `:job_id`; instead it now has a `:job` hash including `:id`. [#428](https://github.com/que-rb/que/pull/428)
- **Documentation**:
    + Improved wording of transaction recommendation in the readme for destroying a job. [#417](https://github.com/que-rb/que/pull/417)
    + Added [que-view](https://github.com/kortirso/que-view) to the list of Que-compatible projects in the readme: "A Rails engine-based UI for inspecting your job queue". [#418](https://github.com/que-rb/que/pull/418)

## 2.3.0 (2023-10-16)

- **Fixed**:
    + Don't clear `ActiveRecord` connections when `run_synchronously` is enabled [#393](https://github.com/que-rb/que/pull/393)

- **Changed**
    + Improve performance of query used by `QueJob#by_job_class` for jobs wrapped by `ActiveJob` [#394](https://github.com/que-rb/que/pull/394)

- **Added**
    + Allow `que` to be started without listen/notify [#395](https://github.com/que-rb/que/pull/395)
    + Support Rails 7.1+ [#403](https://github.com/que-rb/que/pull/403)

## 2.2.1 (2023-04-28)

- **Fixed**:
    + Fixed support for ActiveJob in Ruby 3.2. [#390](https://github.com/que-rb/que/pull/390)

## 2.2.0 (2022-08-29)

- **Changed**:
    + When migrating, now raises an exception when the Que DB schema version is missing from the database. The migrations system records this version in a comment on the `que_jobs` table. [#379](https://github.com/que-rb/que/pull/379)
        *   > Que::Error: Cannot determine Que DB schema version.
            >
            > The que_jobs table is missing its comment recording the Que DB schema version. This is likely due to a bug in Rails schema dump in Rails 7 versions prior to 7.0.3, omitting comments - see https://github.com/que-rb/que/issues/363. Please determine the appropriate schema version from your migrations and record it manually by running the following SQL (replacing version as appropriate):
            >
            > COMMENT ON TABLE que_jobs IS 'version';
- **Removed**:
    + Removed support for upgrading directly from a version of Que prior to v0.5.0 (released on 2014-01-14), which introduced the migrations system. It's too difficult to handle the different DB schemas from prior to this.
- **Internal**:
    + Moved `command_line_interface.rb` from `bin/` to `lib/`. [#378](https://github.com/que-rb/que/pull/378)

## 2.1.0 (2022-08-25)

- **Added**:
    + Added bulk enqueue interface for performance when enqueuing a large number of jobs at once - [docs](docs#enqueueing-jobs-in-bulk).
- **Deprecated**:
    + Deprecated `que_state_notify` trigger (`que_state` notification channel / `job_change` notification message). See [#372](https://github.com/que-rb/que/issues/372). We plan to remove this in a future release - let us know on the issue if you desire otherwise.

This release contains a database migration. You will need to migrate Que to the latest database schema version (7). For example, on ActiveRecord and Rails 6:

```ruby
class UpdateQueTablesToVersion7 < ActiveRecord::Migration[6.0]
  def up
    Que.migrate!(version: 7)
  end

  def down
    Que.migrate!(version: 6)
  end
end
```

## 2.0.0 (2022-08-25)

**Important: Do not upgrade straight to Que 2.** You will need to first update to the latest 1.x version, apply the Que database schema migration, and deploy, before you can safely begin the process of upgrading to Que 2. See the [2.0.0.beta1 changelog entry](#200beta1-2022-03-24) for details.

See beta 2.0.0.beta1, plus:

- **Fixed**:
    + Updated to use non-deprecated method from PG when params are passed (`#async_exec_params`). [#374](https://github.com/que-rb/que/pull/374)

Note that @dtcristo submitted a PR proposing an easier upgrade path to Que 2 and Ruby 3 - [#365](https://github.com/que-rb/que/pull/365). We are yet to properly consider this, but a later release which includes this feature would mean you don't need to simultaneously deploy Que 1.x and 2.x workers during the upgrade.

## 1.4.1 (2022-07-24)

- **Added**
    + Added Ruby version requirement of < 3. For Ruby 3 compatibility, upgrade to Que 2 - [upgrade process](https://github.com/que-rb/que/blob/master/CHANGELOG.md#200beta1-2022-03-24)

## 2.0.0.beta1 (2022-03-24)

**Preliminary release of Ruby 3 support**

**Notable changes**:

* Support for Ruby 3 introduced
* Database schema has changed to split the job arguments `args` column into `args` and `kwargs` columns, for reliable args and kwargs splitting for Ruby 3.
    - The job schema version is now 2. Note that job schema version is distinct from database schema version and Que version. The `job_schema_version` column of the `que_jobs` table no longer defaults and has a not null constraint, so when manually inserting jobs into the table, this must be specified as `2`. If you have a gem that needs to support multiple Que versions, best not to blindly use the value of `Que.job_schema_version`; instead have different code paths depending on the value of `Que.job_schema_version`. You could also use this to know whether keyword arguments are in `args` or `kwargs`.
* Passing a hash literal as the last job argument to be splatted into job keyword arguments is no longer supported.
* Dropped support for providing job options as top-level keyword arguments to `Job.enqueue`, i.e. `queue`, `priority`, `run_at`, `job_class`, and `tags`. Job options now need to be nested under the `job_options` keyword argument instead. See [#336](https://github.com/que-rb/que/pull/336)
* Dropped support for Ruby < 2.7
* Dropped support for Rails < 6.0
* The `#by_args` method on the Job model (for both Sequel and ActiveRecord) now searches based on both args and kwargs, but it performs a subset match instead of an exact match. For instance, if your job was scheduled with `'a', 'b', 'c', foo: 'bar', baz: 1`, `by_args('a', 'b', baz: 1)` would find and return the job.
* This release contains a database migration. You will need to migrate Que to the latest database schema version (6). For example, on ActiveRecord and Rails 6:

```ruby
class UpdateQueTablesToVersion6 < ActiveRecord::Migration[6.0]
  def up
    Que.migrate!(version: 6)
  end

  def down
    Que.migrate!(version: 5)
  end
end
```

**Recommended upgrade process**:

When using Que 2.x, a job enqueued with Ruby 2.7 will run as expected on Ruby 3. We recommend:

1. Upgrade your project to the latest 1.x version of Que (1.3.1+)
    - IMPORTANT: adds support for zero downtime upgrade to Que 2.x, see changelog below
2. Upgrade your project to Ruby 2.7 and Rails 6.x if it is not already
3. Upgrade your project to Que 2.x but stay on Ruby 2.7
    - IMPORTANT: You will need to continue to run Que 1.x workers until all jobs enqueued using Que 1.x (i.e. with a `job_schema_version` of `1`) have been finished. See below
4. Upgrade your project to Ruby 3

*NOTES:*

* If you were already running Ruby 2.7 and were not passing a hash literal as the last job argument, you *may* be able to upgrade a running system without draining the queue, though this is not recommended.
* For all other cases, you will need to follow the recommended process above or first completely drain the queue (stop enqueuing new jobs and finish processing any jobs in the database, including cleaning out any expired jobs) before upgrading.

**Deploying Que 1.x and 2.x workers simultaneously**:

To run workers with two different versions of Que, you'll probably need to temporarily duplicate your gem bundle, with the Que version being the only difference. e.g.:

- Copy your `Gemfile` and `Gemfile.lock` into a directory called `que-1-gemfile`
- Set a suitable Que version in each `Gemfile`
- Update the bundle at `que-1-gemfile/Gemfile.lock` using `BUNDLE_GEMFILE=que-1-gemfile/Gemfile bundle`
- Create a second deployment of Que, but with your `que` command prefixed with `BUNDLE_GEMFILE=que-1-gemfile/Gemfile`

We'd appreciate feedback on your experience upgrading to and running Que 2. Feel free to post on our Discord, or if you run into trouble, open an issue on GitHub.

## 1.4.0 (2022-03-23)

- **Fixed**
    + The poller will no longer sleep when jobs exist for only some of its priorities. It now skips sleeping when a poll returns more jobs than the lowest priority requested. [#349](https://github.com/que-rb/que/pull/349).
        * An alternative was considered which skipped polling when only some of the waiting worker priorities would be fully utilised ([diagram explanation](https://github.com/que-rb/que/pull/348#discussion_r819213357)); but this was decided against for code complexity reasons. [#348](https://github.com/que-rb/que/pull/348)
- **Deprecated**:
    + Deprecated `--minimum-buffer-size` option. It was not actually used, and will be removed in v2.0.0. [#346](https://github.com/que-rb/que/pull/346)
        * It became used in 1.0.0.beta4, and that changelog entry has been updated to reflect this.
- **Documentation**:
    + Reformatted the changelog to be more consistent, including adding links to all issue/PR numbers. [#347](https://github.com/que-rb/que/pull/347)

## 1.3.1 (2022-02-25)

Unfortunately, v1.3.0 was broken. Follow its upgrade instructions, but use this version instead.

- **Fixed**
    + Fixed startup error: `undefined method 'job_schema_version' for Que:Module`, in [#343](https://github.com/que-rb/que/pull/343)

## 1.3.0 (2022-02-25)

**ACTION REQUIRED**

This release will allow you to safely upgrade to Que 2 when it comes out, without first needing to empty your `que_jobs` table.

**You will need to first update to this version, apply the Que schema migration, and deploy, before you can safely begin the process of upgrading to Que 2.**

Que 2 will bring Ruby 3 support, but to do that, the job arguments in the `que_jobs` table will need to be split into two columns - repurposing the existing one for positional arguments only (`args`), and adding a new one for keyword arguments (`kwargs`). This is so that Que running in Ruby 3, when reading job arguments stored in the database, can disambiguate between keyword arguments and a last positional argument hash.

The args split hasn't happened yet, but when it does, we still need to be able to successfully process all the existing queued jobs which have their keyword arguments in the `args` column still. Our solution is for you to have both Que 1 workers and Que 2 workers operating simultaneously during the upgrade, each processing only the jobs enqueued from that version. Once all the Que 1 jobs are processed, the Que 1 workers can be retired.

To allow the different worker versions to tell which jobs belong to which, we've added a new column to the `que_jobs` table in this version, `job_schema_version`. Jobs enqueued with Que 1 will have a `1` here, and jobs from Que 2 will have a `2`. Que schema migration 5 will default the job schema version of all existing jobs to `1`.

You will need to migrate Que to the latest Que schema version (5). For instance, on ActiveRecord and Rails 6:

```ruby
class UpdateQueTablesToVersion5 < ActiveRecord::Migration[6.0]
  def up
    Que.migrate!(version: 5)
  end
  def down
    Que.migrate!(version: 4)
  end
end
```

You must apply the schema migration and deploy to upgrade all workers.

No further action is required from you at this stage. The Que 2 release changelog will provide full upgrade instructions for the process briefly described above of simultaneously running both Que 1 & 2 workers. Note that you won't be required to upgrade from Ruby 2.7 to Ruby 3 at the same time as upgrading to Que 2.

If you use any Que plugins or custom code that interacts with the `que_jobs` table, before you can upgrade to Que 2, you will need to make sure they are updated for compatibility with Que 2: They'll need to make use of the `kwargs` column, and when inserting jobs, put a `2` into the `job_schema_version` column rather than continue to rely on its soon-to-be-removed default of `1`.

**Other improvements**:

- **Features**:
    + Log config on startup, in [#337](https://github.com/que-rb/que/pull/337)
- **Internal**:
    + Added Git pre-push hook, in [#338](https://github.com/que-rb/que/pull/338)
    + Documented our gem release process, in [#341](https://github.com/que-rb/que/pull/341)

## 1.2.0 (2022-02-23)

- **Deprecated**
    + Providing job options as top level keyword arguments to Job.enqueue is now deprecated. Support will be dropped in `2.0`. Job options should be nested under the `job_options` keyword arg instead. See [#336](https://github.com/que-rb/que/pull/336)

## 1.1.0 (2022-02-21)

- **Features**:
    + Add backtrace to errors, by [@trammel](https://github.com/trammel) in [#328](https://github.com/que-rb/que/pull/328)
- **Internal**:
    + Add Dockerised development environment, in [#324](https://github.com/que-rb/que/pull/324)

## 1.0.0 (2022-01-24)

_This release does not add any changes on top of 1.0.0.beta5._

## 1.0.0.beta5 (2021-12-23)

- **Bug fixes and improvements**
    + Add more context to error message when config files fail to load. by [@trammel](https://github.com/trammel) in [#293](https://github.com/que-rb/que/pull/293)
    + Fix lock leak on PostgreSQL 12 and later by [@jasoncodes](https://github.com/jasoncodes) in [#298](https://github.com/que-rb/que/pull/298)
    + Fix deadlock issue [#318](https://github.com/que-rb/que/pull/318)
    + Fix thread attrition issue [#321](https://github.com/que-rb/que/pull/321)
- **Rails fixes:**
    + Set schema in table_name for ActiveRecord model by [@nikitug](https://github.com/nikitug) in [#274](https://github.com/que-rb/que/pull/274)
- **Documentation:**
    + Add link to que-locks for exclusive job locking by [@airhorns](https://github.com/airhorns) in [#263](https://github.com/que-rb/que/pull/263)
    [`5259303`](https://github.com/que-rb/que/commit/52593031a7eef2d52ac38eceb2d8df776ec74090)
    + Fix links to Writing Reliable Jobs by [@nikitug](https://github.com/nikitug) in [#273](https://github.com/que-rb/que/pull/273)
    + Add build badge to README by [@jonathanhefner](https://github.com/jonathanhefner) in [#278](https://github.com/que-rb/que/pull/278)
    + Fix ToC links in docs by [@swrobel](https://github.com/swrobel) in [#287](https://github.com/que-rb/que/pull/287)
    + Note all Rails queue names that must be changed by [@swrobel](https://github.com/swrobel) in [#296](https://github.com/que-rb/que/pull/296)
    + Add instructions for how to start Que by [@xcskier56](https://github.com/xcskier56) in [#292](https://github.com/que-rb/que/pull/292)
- **CI/tests**
    + Fix CI failure from Docker Postgres image by [@jonathanhefner](https://github.com/jonathanhefner) in [#275](https://github.com/que-rb/que/pull/275)
    + Test with Ruby 2.7 by [@jonathanhefner](https://github.com/jonathanhefner) in [#276](https://github.com/que-rb/que/pull/276)
    + Run GitHub build workflow on push by [@jonathanhefner](https://github.com/jonathanhefner) in [#277](https://github.com/que-rb/que/pull/277)
**Full Changelog**: [`v1.0.0.beta4...v1.0.0.beta5`](https://github.com/que-rb/que/compare/v1.0.0.beta4...v1.0.0.beta5)
**Unless an issue is found we intend for this release to become v1.0.0 proper.**

## 1.0.0.beta4 (2020-01-17)

- Rails 6 compatibility: Fix time parsing [#249](https://github.com/que-rb/que/pull/249) and [5ddddd5](https://github.com/que-rb/que/commit/5ddddd5ebac6153d7a683ef08c86bced8e03fb51)
- Cleaner sequel usage, in [#257](https://github.com/que-rb/que/pull/257)
- Documentation improvements: [#264](https://github.com/que-rb/que/pull/264), [#269](https://github.com/que-rb/que/pull/269), [#261](https://github.com/que-rb/que/pull/261), [#231](https://github.com/que-rb/que/pull/231)
- The `--minimum-buffer-size` option is now unused

## 1.0.0.beta3 (2018-05-18)

- Added support for customizing log levels for `job_worked` events ([#217](https://github.com/que-rb/que/issues/217)).
- Began logging all `job_errored` events at the `ERROR` log level.
- Fixed the Railtie when running in test mode ([#214](https://github.com/que-rb/que/issues/214)).
- Tweaked the meanings of worker-priorities and worker-count options in the CLI, to better support use cases with low worker counts ([#216](https://github.com/que-rb/que/issues/216)).

## 1.0.0.beta2 (2018-04-13)

- **A schema upgrade to version 4 will be required for this release.** See [the migration doc](https://github.com/que-rb/que/blob/master/docs/migrating.md) for information if you're upgrading from a previous release.
    + Please note that this migration requires a rewrite of the jobs table, which makes it O(n) with the size of the table. If you have a very large backlog of jobs you may want to schedule downtime for this migration.
- Que's implementation has been changed from one in which worker threads hold their own PG connections and lock their own jobs to one in which a single thread (and PG connection) locks jobs through LISTEN/NOTIFY and batch polling, and passes jobs along to worker threads. This has many benefits, including:
    + Jobs queued for immediate processing can be actively distributed to workers with LISTEN/NOTIFY, which is more efficient than having workers repeatedly poll for new jobs.
    + When polling is necessary (to pick up jobs that are scheduled for the future or that need to be retried due to errors), jobs can be locked and fetched in batches, rather than one at a time.
    + Individual workers no longer need to monopolize their own (usually idle) connections while working jobs, so Ruby processes will require fewer Postgres connections.
    + PgBouncer or another external connection pool can be used for workers' connections (though not for the connection used to lock and listen for jobs).
- Other features introduced in this version include:
    + Much better support for all versions of ActiveJob.
        * In particular, you may (optionally) include `Que::ActiveJob::JobExtensions` into `ApplicationJob` to get support for all of Que's job helper methods.
    + Custom middleware that wrap running jobs and executing SQL statements are now supported.
    + Support for categorizing jobs with tags.
    + Support for configuring a `maximum_retry_count` on individual job classes.
    + Job configuration options are now inheritable, so job class hierarchies are more useful.
    + There are now built-in models for ActiveRecord and Sequel to allow inspecting the queue easily.
    + Jobs that have finished working may optionally be retained in the database indefinitely.
        * To keep a job record, replace the `destroy` calls in your jobs with `finish`. `destroy` will still delete records entirely, for jobs that you don't want to keep.
        * If you don't resolve a job yourself one way or another, Que will still `destroy` the job for you by default.
        * Finished jobs have a timestamp set in the finished_at column.
    + Jobs that have errored too many times will now be marked as expired, and won't be retried again.
        * You can configure a maximum_retry_count in your job classes, to set the threshold at which a job will be marked expired. The default is 15.
        * To manually mark a job as expired (and keep it in the database but not try to run it again) you can call `expire` helper in your job.
    + You can now set job priority thresholds for individual workers, to ensure that there will always be space available for high-priority jobs.
    + `Que.job_states` returns a list of locked jobs and the hostname/pid of the Ruby processes that have locked them.
    + `Que.connection_proc=` has been added, to allow for the easy integration of custom connection pools.
- In keeping with semantic versioning, the major version is being bumped since the new implementation requires some backwards-incompatible changes. These changes include:
    + Support for MRI Rubies before 2.2 has been dropped.
    + Support for Postgres versions before 9.5 has been dropped (JSONB and upsert support is required).
    + JRuby support has been dropped. It will be reintroduced whenever the jruby-pg gem is production-ready.
    + The `que:work` rake task has been removed. Use the `que` executable instead.
        * Therefore, configuring workers using QUE_* environment variables is no longer supported. Please pass the appropriate options to the `que` executable instead.
    + The `mode` setter has been removed.
        * To run jobs synchronously when they are enqueued (the old `:sync` behavior) you can set `Que.run_synchronously = true`.
        * To start up the worker pool (the old :async behavior) you should use the `que` executable to start up a worker process. There's no longer a supported API for running workers outside of the `que` executable.
    + The following methods are not meaningful under the new implementation and have been removed:
        * The `Que.wake_interval` getter and setter.
        * The `Que.worker_count` getter and setter.
        * `Que.wake!`
        * `Que.wake_all!`
    + Since Que needs a dedicated Postgres connection to manage job locks, running Que through a single PG connection is no longer supported.
        * It's not clear that anyone ever actually did this.
    + `Que.worker_states` has been removed, as the connection that locks a job is no longer the one that the job is using to run. Its functionality has been partially replaced with `Que.job_states`.
    + When using Rails, for simplicity, job attributes and keys in argument hashes are now converted to symbols when retrieved from the database, rather than being converted to instances of HashWithIndifferentAccess.
    + Arguments passed to jobs are now deep-frozen, to prevent unexpected behavior when the args are mutated and the job is reenqueued.
    + Since JSONB is now used to store arguments, the order of argument hashes is no longer maintained.
        * It wouldn't have been a good idea to rely on this anyway.
    + Calling Que.log() directly is no longer supported/recommended.
    + Features marked as deprecated in the final 0.x releases have been removed.
- Finally, if you've built up your own tooling and customizations around Que, you may need to be aware of some DB schema changes made in the migration to schema version #4.
    + The `job_id` column has been renamed `id` and is now the primary key. This makes it easier to manage the queue using an ActiveRecord model.
    + Finished jobs are now kept in the DB, unless you explicitly call `destroy`. If you want to query the DB for only jobs that haven't finished yet, add a `WHERE finished_at IS NULL` condition to your query, or use the not_finished scope on one of the provided ORM models.
    + There is now an `expired_at` timestamp column, which is set when a job reaches its maximum number of retries and will not be attempted again.
    + Due to popular demand, the default queue name is now "default" rather than an empty string. The migration will move pending jobs under the "" queue to the "default" queue.
    + The `last_error` column has been split in two, to `last_error_message` and `last_error_backtrace`. These two columns are now limited to 500 and 10,000 characters, respectively. The migration will split old error data correctly, and truncate it if necessary.
    + Names for queues and job classes are now limited to 500 characters, which is still far longer than either of these values should reasonably be.
    + There is now a `data` JSONB column which is used to support various ways of organizing jobs (setting tags on them, etc).

## 1.0.0.beta (2017-10-25)

- **A schema upgrade to version 4 will be required for this release.** See [the migration doc](https://github.com/que-rb/que/blob/master/docs/migrating.md) for information if you're upgrading from a previous release.
    + Please note that this migration requires a rewrite of the jobs table, which makes it O(n) with the size of the table. If you have a very large backlog of jobs you may want to schedule downtime for this migration.
- Que's implementation has been changed from one in which worker threads hold their own PG connections and lock their own jobs to one in which a single thread (and PG connection) locks jobs through LISTEN/NOTIFY and batch polling, and passes jobs along to worker threads. This has many benefits, including:
    + Jobs queued for immediate processing can be actively distributed to workers with LISTEN/NOTIFY, which is more efficient than having workers repeatedly poll for new jobs.
    + When polling is necessary (to pick up jobs that are scheduled for the future or that need to be retried due to errors), jobs can be locked and fetched in batches, rather than one at a time.
    + Individual workers no longer need to monopolize their own (usually idle) connections while working jobs, so Ruby processes will require fewer Postgres connections.
    + PgBouncer or another external connection pool can be used for workers' connections (though not for the connection used to lock and listen for jobs).
- Other features introduced in this version include:
    + Much better support for all versions of ActiveJob.
        * In particular, you may (optionally) include `Que::ActiveJob::JobExtensions` into `ApplicationJob` to get support for all of Que's job helper methods.
    + Custom middleware that wrap running jobs are now supported.
    + Support for categorizing jobs with tags.
    + Support for configuring a `maximum_retry_count` on individual job classes.
    + Job configuration options are now inheritable, so job class hierarchies are more useful.
    + There are now built-in models for ActiveRecord and Sequel to allow inspecting the queue easily.
    + Jobs that have finished working may optionally be retained in the database indefinitely.
        * To keep a job record, replace the `destroy` calls in your jobs with `finish`. `destroy` will still delete records entirely, for jobs that you don't want to keep.
        * If you don't resolve a job yourself one way or another, Que will still `destroy` the job for you by default.
        * Finished jobs have a timestamp set in the finished_at column.
    + Jobs that have errored too many times will now be marked as expired, and won't be retried again.
        * You can configure a maximum_retry_count in your job classes, to set the threshold at which a job will be marked expired. The default is 15.
        * To manually mark a job as expired (and keep it in the database but not try to run it again) you can call `expire` helper in your job.
    + You can now set job priority thresholds for individual workers, to ensure that there will always be space available for high-priority jobs.
    + `Que.job_states` returns a list of locked jobs and the hostname/pid of the Ruby processes that have locked them.
    + `Que.connection_proc=` has been added, to allow for the easy integration of custom connection pools.
- In keeping with semantic versioning, the major version is being bumped since the new implementation requires some backwards-incompatible changes. These changes include:
    + Support for MRI Rubies before 2.2 has been dropped.
    + Support for Postgres versions before 9.5 has been dropped (JSONB and upsert support is required).
    + JRuby support has been dropped. It will be reintroduced whenever the jruby-pg gem is production-ready.
    + The `que:work` rake task has been removed. Use the `que` executable instead.
        * Therefore, configuring workers using QUE_* environment variables is no longer supported. Please pass the appropriate options to the `que` executable instead.
    + The `mode` setter has been removed.
        * To run jobs synchronously when they are enqueued (the old `:sync` behavior) you can set `Que.run_synchronously = true`.
        * To start up the worker pool (the old :async behavior) you should use the `que` executable to start up a worker process. There's no longer a supported API for running workers outside of the `que` executable.
    + The following methods are not meaningful under the new implementation and have been removed:
        * The `Que.wake_interval` getter and setter.
        * The `Que.worker_count` getter and setter.
        * `Que.wake!`
        * `Que.wake_all!`
    + Since Que needs a dedicated Postgres connection to manage job locks, running Que through a single PG connection is no longer supported.
        * It's not clear that anyone ever actually did this.
    + `Que.worker_states` has been removed, as the connection that locks a job is no longer the one that the job is using to run. Its functionality has been partially replaced with `Que.job_states`.
    + When using Rails, for simplicity, job attributes and keys in argument hashes are now converted to symbols when retrieved from the database, rather than being converted to instances of HashWithIndifferentAccess.
    + Arguments passed to jobs are now deep-frozen, to prevent unexpected behavior when the args are mutated and the job is reenqueued.
    + Since JSONB is now used to store arguments, the order of argument hashes is no longer maintained.
        * It wouldn't have been a good idea to rely on this anyway.
    + Calling Que.log() directly is no longer supported/recommended.
    + Features marked as deprecated in the final 0.x releases have been removed.
- Finally, if you've built up your own tooling and customizations around Que, you may need to be aware of some DB schema changes made in the migration to schema version #4.
    + The `job_id` column has been renamed `id` and is now the primary key. This makes it easier to manage the queue using an ActiveRecord model.
    + Finished jobs are now kept in the DB, unless you explicitly call `destroy`. If you want to query the DB for only jobs that haven't finished yet, add a `WHERE finished_at IS NULL` condition to your query, or use the not_finished scope on one of the provided ORM models.
    + There is now an `expired_at` timestamp column, which is set when a job reaches its maximum number of retries and will not be attempted again.
    + Due to popular demand, the default queue name is now "default" rather than an empty string. The migration will move pending jobs under the "" queue to the "default" queue.
    + The `last_error` column has been split in two, to `last_error_message` and `last_error_backtrace`. These two columns are now limited to 500 and 10,000 characters, respectively. The migration will split old error data correctly, and truncate it if necessary.
    + Names for queues and job classes are now limited to 500 characters, which is still far longer than either of these values should reasonably be.
    + There is now a `data` JSONB column which is used to support various ways of organizing jobs (setting tags on them, etc).

## 0.14.3 (2018-03-02)

- Recorded errors now always include the error class, so that empty error messages can still be helpful. (  joehorsnell)
- Recorded error messages are now truncated to the first 500 characters.

## 0.14.2 (2018-01-05)

- Deprecate the Que.disable_prepared_statements= accessors.
- Add Que.use_prepared_statements= configuration accessors.
- Update the generated Rails migration to declare a version. (NARKOZ)

## 0.14.1 (2017-12-14)

- Fix a bug with typecasting boolean values on Rails 5+.

## 0.14.0 (2017-08-11)

- Fix incompatibility with Rails 5.1.
- Drop support for waking an in-process worker when an ActiveRecord transaction commits.

## 0.13.1 (2017-07-05)

- Fix issue that caused error stacktraces to not be persisted in most cases.

## 0.13.0 (2017-06-08)

- Fix recurring JSON issues by dropping MultiJson support. Previously MultiJson was detected and used automatically, and now it's just ignored and stdlib JSON used instead, so this shouldn't require any code changes.

## 0.12.3 (2017-06-01)

- Fix incompatibility with MultiJson introduced by the previous release.

## 0.12.2 (2017-06-01)

- Fix security vulnerability in parsing JSON from the DB (by specifying create_additions: false). This shouldn't be a concern unless you were passing untrusted user input in your job arguments. (hmac)

## 0.12.1 (2017-01-22)

- Fix incompatibility with Rails 5.0. ([#166](https://github.com/que-rb/que/issues/166)) (nbibler, thedarkone)

## 0.12.0 (2016-09-09)

- The error_handler configuration option has been renamed to error_notifier, which is more descriptive of what it's actually supposed to do. You can still use error_handler for configuration, but you'll get a warning.
- Introduced a new framework for handling errors on a per-job basis. See the docs for more information. ([#106](https://github.com/que-rb/que/pull/106), [#147](https://github.com/que-rb/que/issues/147))

## 0.11.6 (2016-07-01)

- Fix for operating in nested transactions in Rails 5.0. ([#160](https://github.com/que-rb/que/pull/160)) (greysteil)

## 0.11.5 (2016-05-13)

- Fix error when running `que -v`. ([#154](https://github.com/que-rb/que/pull/154)) (hardbap)

## 0.11.4 (2016-03-03)

- Fix incompatibility with ActiveRecord 5.0.0.beta3. ([#143](https://github.com/que-rb/que/issues/143), [#144](https://github.com/que-rb/que/pull/144)) (joevandyk)

## 0.11.3 (2016-02-26)

- Fixed bug with displaying the current version of the que executable. ([#122](https://github.com/que-rb/que/pull/122)) (hardbap)
- Output to STDOUT when running via the executable or rake task is no longer buffered. This prevented logging in some cases. ([#129](https://github.com/que-rb/que/pull/129)) (hmarr)
- Officially added support for Ruby 2.2 and 2.3.
- String literals are now frozen on Ruby 2.3.

## 0.11.2 (2015-09-09)

- Fix Job class constantizing when ActiveSupport isn't loaded. ([#121](https://github.com/que-rb/que/pull/121)) (godfat)

## 0.11.1 (2015-09-04)

- The `rake que:work` rake task that was specific to Rails has been deprecated and will be removed in Que 1.0. A deprecation warning will display when it is run.

## 0.11.0 (2015-09-04)

- A command-line program has been added that can be used to work jobs in a more flexible manner than the previous rake task. Run `que -h` for more information.
- The worker pool will no longer start automatically in the same process when running the rails server - this behavior was too prone to breakage. If you'd like to recreate the old behavior, you can manually set `Que.mode = :async` in your app whenever conditions are appropriate (classes have loaded, a database connection has been established, and the process will not be forking).
- Add a Que.disable_prepared_transactions= configuration option, to make it easier to use tools like pgbouncer. ([#110](https://github.com/que-rb/que/issues/110))
- Add a Que.json_converter= option, to configure how arguments are transformed before being passed to the job. By default this is set to the `Que::INDIFFERENTIATOR` proc, which provides simple indifferent access (via strings or symbols) to args hashes. If you're using Rails, the default is to convert the args to HashWithIndifferentAccess instead. You can also pass it the Que::SYMBOLIZER proc, which will destructively convert all keys in the args hash to symbols (this will probably be the default in Que 1.0). If you want to define a custom converter, you will usually want to pass this option a proc, and you'll probably want it to be recursive. See the implementations of Que::INDIFFERENTIATOR and Que::SYMBOLIZER for examples. ([#113](https://github.com/que-rb/que/issues/113))
- When using Que with ActiveRecord, workers now call `ActiveRecord::Base.clear_active_connections!` between jobs. This cleans up connections that ActiveRecord leaks when it is used to access mutliple databases. ([#116](https://github.com/que-rb/que/pull/116))
- If it exists, use String#constantize to constantize job classes, since ActiveSupport's constantize method behaves better with Rails' autoloading. ([#115](https://github.com/que-rb/que/issues/115), [#120](https://github.com/que-rb/que/pull/120)) (joevandyk)

## 0.10.0 (2015-03-18)

- When working jobs via the rake task, Rails applications are now eager-loaded if present, to avoid problems with multithreading and autoloading. ([#96](https://github.com/que-rb/que/pull/96)) (hmarr)
- The que:work rake task now uses whatever logger Que is configured to use normally, rather than forcing the use of STDOUT. ([#95](https://github.com/que-rb/que/issues/95))
- Add Que.transaction() helper method, to aid in transaction management in migrations or when the user's ORM doesn't provide one. ([#81](https://github.com/que-rb/que/issues/81))

## 0.9.2 (2015-02-05)

- Fix a bug wherein the at_exit hook in the railtie wasn't waiting for jobs to finish before exiting.
- Fix a bug wherein the que:work rake task wasn't waiting for jobs to finish before exiting. ([#85](https://github.com/que-rb/que/pull/85)) (tycooon)

## 0.9.1 (2015-01-11)

- Use now() rather than 'now' when inserting jobs, to avoid using an old value as the default run_at in prepared statements. ([#74](https://github.com/que-rb/que/pull/74)) (bgentry)

## 0.9.0 (2014-12-16)

- The error_handler callable is now passed two objects, the error and the job that raised it. If your current error_handler is a proc, as recommended in the docs, you shouldn't need to make any code changes, unless you want to use the job in your error handling. If your error_handler is a lambda, or another callable with a strict arity requirement, you'll want to change it before upgrading. ([#69](https://github.com/que-rb/que/pull/69)) (statianzo)

## 0.8.2 (2014-10-12)

- Fix errors raised during rollbacks in the ActiveRecord adapter, which remained silent until Rails 4.2. ([#64](https://github.com/que-rb/que/pull/64), [#65](https://github.com/que-rb/que/pull/65)) (Strech)

## 0.8.1 (2014-07-28)

- Fix regression introduced in the `que:work` rake task by the `mode` / `worker_count` disentangling in 0.8.0. ([#50](https://github.com/que-rb/que/issues/50))

## 0.8.0 (2014-07-12)

- A callable can now be set as the logger, like `Que.logger = proc { MyLogger.new }`. Que uses this in its Railtie for cleaner initialization, but it is also available for public use.
- `Que.mode=` and `Que.worker_count=` now function independently. That is, setting the worker_count to a nonzero number no longer sets mode = :async (triggering the pool to start working jobs), and setting it to zero no longer sets mode = :off. Similarly, setting the mode to :async no longer sets the worker_count to 4 from 0, and setting the mode to :off no longer sets the worker_count to 0. This behavior was changed because it was interfering with configuration during initialization of Rails applications, and because it was unexpected. ([#47](https://github.com/que-rb/que/issues/47))
- Fixed a similar bug wherein setting a wake_interval during application startup would break worker awakening after the process was forked.

## 0.7.3 (2014-05-19)

- When mode = :sync, don't touch the database at all when running jobs inline. Needed for ActiveJob compatibility ([#46](https://github.com/que-rb/que/issues/46)).

## 0.7.2 (2014-05-18)

- Fix issue wherein intermittent worker wakeups would not work after forking ([#44](https://github.com/que-rb/que/issues/44)).

## 0.7.1 (2014-04-29)

- Fix errors with prepared statements when ActiveRecord reconnects to the database. (dvrensk)
- Don't use prepared statements when inside a transaction. This negates the risk of a prepared statement error harming the entire transaction. The query that benefits the most from preparation is the job-lock CTE, which is never run in a transaction, so the performance impact should be negligible.

## 0.7.0 (2014-04-09)

- `JobClass.queue(*args)` has been deprecated and will be removed in version 1.0.0. Please use `JobClass.enqueue(*args)` instead.
- The `@default_priority` and `@default_run_at` variables have been deprecated and will be removed in version 1.0.0. Please use `@priority` and `@run_at` instead, respectively.
- Log lines now include the process pid - its omission in the previous release was an oversight.
- The [Pond gem](https://github.com/chanks/pond) is now supported as a connection. It is very similar to the ConnectionPool gem, but creates connections lazily and is dynamically resizable.

## 0.6.0 (2014-02-04)

- **A schema upgrade to version 3 is required for this release.** See [the migration doc](https://github.com/que-rb/que/blob/master/docs/migrating.md) for information if you're upgrading from a previous release.
- You can now run a job's logic directly (without enqueueing it) like `MyJob.run(arg1, arg2, other_arg: arg3)`. This is useful when a job class encapsulates logic that you want to invoke without involving the entire queue.
- You can now check the current version of Que's database schema with `Que.db_version`.
- The method for enqueuing a job has been renamed from `MyJob.queue` to `MyJob.enqueue`, since we were beginning to use the word 'queue' in a LOT of places. `MyJob.queue` still works, but it may be removed at some point.
- The variables for setting the defaults for a given job class have been changed from `@default_priority` to `@priority` and `@default_run_at` to `@run_at`. The old variables still work, but like `Job.queue`, they may be removed at some point.
- Log lines now include the machine's hostname, since a pid alone may not uniquely identify a process.
- Multiple queues are now supported. See [the docs](https://github.com/que-rb/que/blob/master/docs/multiple_queues.md) for details. (chanks, joevandyk)
- Rubinius 2.2 is now supported. (brixen)
- Job classes may now define their own logic for determining the retry interval when a job raises an error. See [error handling](https://github.com/que-rb/que/blob/master/docs/error_handling.md) for more information.

## 0.5.0 (2014-01-14)

- When running a worker pool inside your web process on ActiveRecord, Que will now wake a worker once a transaction containing a queued job is committed. (joevandyk, chanks)
- The `que:work` rake task now has a default wake_interval of 0.1 seconds, since it relies exclusively on polling to pick up jobs. You can set a QUE_WAKE_INTERVAL environment variable to change this. The environment variable to set a size for the worker pool in the rake task has also been changed from WORKER_COUNT to QUE_WORKER_COUNT.
- Officially support Ruby 1.9.3. Note that due to the Thread#kill problems (see "Remove Que.stop!" below) there's a danger of data corruption when running under 1.9, though.
- The default priority for jobs is now 100 (it was 1 before). Like always (and like delayed_job), a lower priority means it's more important. You can migrate the schema version to 2 to set the new default value on the que_jobs table, though it's only necessary if you're doing your own INSERTs - if you use `MyJob.queue`, it's already taken care of.
- Added a migration system to make it easier to change the schema when updating Que. You can now write, for example, `Que.migrate!(version: 2)` in your migrations. Migrations are run transactionally.
- The logging format has changed to be more easily machine-readable. You can also now customize the logging format by assigning a callable to Que.log_formatter=. See the new doc on [logging](https://github.com/que-rb/que/blob/master/docs/logging.md)) for details. The default logger level is INFO - for less critical information (such as when no jobs were found to be available or when a job-lock race condition has been detected and avoided) you can set the QUE_LOG_LEVEL environment variable to DEBUG.
- MultiJson is now a soft dependency. Que will use it if it is available, but it is not required.
- Remove Que.stop!.

    Using Thread#raise to kill workers is a bad idea - the results are unpredictable and nearly impossible to spec reliably. Its purpose was to prevent premature commits in ActiveRecord/Sequel when a thread is killed during shutdown, but it's possible to detect that situation on Ruby 2.0+, so this is really better handled by the ORMs directly. See the pull requests for [Sequel](https://github.com/jeremyevans/sequel/pull/752) and [ActiveRecord](https://github.com/rails/rails/pull/13656).

    Now, when a process exits, if the worker pool is running (whether in a rake task or in a web process) the exit will be stalled until all workers have finished their current jobs. If you have long-running jobs, this may take a long time. If you need the process to exit immediately, you can SIGKILL without any threat of commiting prematurely.

## 0.4.0 (2014-01-05)

- Que.wake_all! was added, as a simple way to wake up all workers in the pool.
- Que.sleep_period was renamed to the more descriptive Que.wake_interval.
- When queueing a job, Que will wait until the current transaction commits and then wake a background worker, if possible. This allows newly queued jobs to be started immediately instead of waiting for a worker to wake up and poll, which may be up to `Que.wake_interval` seconds.

    This feature currently only works with Sequel, since there doesn't seem to be a clean way to do it on ActiveRecord (if anyone can figure one out, please let me know). Note that if you're using ActiveRecord, you can always manually trigger a single worker to wake up and check for work by manually calling Que.wake! after your transaction completes.
- Add Que.job_stats, which queries the database and returns statistics on the different job classes - for each class, how many are queued, how many are currently being worked, what is the highest error_count, and so on.
- Add Que.worker_states, which queries the database and returns all currently-locked jobs and info on their workers' connections - what and when was the last query they ran, are they waiting on locks, and so on.
- Have Que only clear advisory locks that it has taken when locking jobs, and not touch any that may have been taken by other code using the same connection.
- Add Que.worker_count, to retrieve the current number of workers in the pool of the current process.
- Much more internal cleanup.

## 0.3.0 (2013-12-21)

- Add Que.stop!, which immediately kills all jobs being worked in the process.

    This can leave database connections and such in an unpredictable state, and so should only be used when the process is exiting.
- Use Que.stop! to safely handle processes that exit while Que is running.

    Previously, a job that was in the middle of a transaction when the process was killed with SIGINT or SIGTERM would have had its work committed prematurely.
- Clean up internals and hammer out several race conditions.

## 0.2.0 (2013-11-30)

- Officially support JRuby 1.7.5+. Earlier versions may work.

    JRuby support requires the use of the `jruby-pg` gem, though that gem seems to currently be incompatible with ActiveRecord, so the ActiveRecord adapter specs don't pass (or even run). It works fine with Sequel and the other adapters, though.
- Officially support Rubinius 2.1.1+. Earlier versions may work.
- Use `multi_json` so we always use the fastest JSON parser available. (BukhariH)
- :sync mode now ignores scheduled jobs (jobs queued with a specific run_at).

## 0.1.0 (2013-11-18)

- Initial public release, after a test-driven rewrite.
- Officially support Ruby 2.0.0 and Postgres 9.2+.
- Also support ActiveRecord and bare PG::Connections, in or out of a ConnectionPool.
- Added a Railtie for easier setup with Rails, as well as a migration generator.

## 0.0.1 (2013-11-07)

- Copy-pasted from an app of mine. Very Sequel-specific. Nobody look at it, let's pretend it never happened.
