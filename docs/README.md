# Que documentation

<!-- MarkdownTOC autolink=true -->

- [Command Line Interface](#command-line-interface)
  - [`worker-priorities` and `worker-count`](#worker-priorities-and-worker-count)
  - [`poll-interval`](#poll-interval)
  - [`maximum-buffer-size`](#maximum-buffer-size)
  - [`connection-url`](#connection-url)
  - [`wait-period`](#wait-period)
  - [`log-internals`](#log-internals)
- [Advanced Setup](#advanced-setup)
  - [Using ActiveRecord Without Rails](#using-activerecord-without-rails)
  - [Managing the Jobs Table](#managing-the-jobs-table)
  - [Other Setup](#other-setup)
- [Error Handling](#error-handling)
  - [Error Notifications](#error-notifications)
  - [Error-Specific Handling](#error-specific-handling)
- [Inspecting the Queue](#inspecting-the-queue)
  - [Job Stats](#job-stats)
  - [Custom Queries](#custom-queries)
    - [ActiveRecord Example](#activerecord-example)
    - [Sequel Example](#sequel-example)
- [Managing Workers](#managing-workers)
  - [Working Jobs Via Executable](#working-jobs-via-executable)
  - [Thread-Unsafe Application Code](#thread-unsafe-application-code)
- [Logging](#logging)
  - [Logging Job Completion](#logging-job-completion)
- [Migrating](#migrating)
- [Multiple Queues](#multiple-queues)
- [Shutting Down Safely](#shutting-down-safely)
- [Using Plain Postgres Connections](#using-plain-postgres-connections)
  - [Using ConnectionPool or Pond](#using-connectionpool-or-pond)
  - [Using Any Other Connection Pool](#using-any-other-connection-pool)
- [Using Sequel](#using-sequel)
- [Using Que With ActiveJob](#using-que-with-activejob)
- [Job Helper Methods](#job-helper-methods)
  - [`destroy`](#destroy)
  - [`finish`](#finish)
  - [`expire`](#expire)
  - [`retry_in`](#retry_in)
  - [`error_count`](#error_count)
  - [`default_resolve_action`](#default_resolve_action)
- [Writing Reliable Jobs](#writing-reliable-jobs)
  - [Timeouts](#timeouts)
- [Job Options](#job-options)
  - [`queue`](#queue)
  - [`priority`](#priority)
  - [`run_at`](#run_at)
  - [`job_class`](#job_class)
  - [`tags`](#tags)
- [Middleware](#middleware)
  - [Defining Middleware For Jobs](#defining-middleware-for-jobs)
  - [Defining Middleware For SQL statements](#defining-middleware-for-sql-statements)
- [Vacuuming](#vacuuming)
- [Enqueueing jobs in bulk](#enqueueing-jobs-in-bulk)
- [Expired jobs](#expired-jobs)
- [Finished jobs](#finished-jobs)

<!-- /MarkdownTOC -->

## Command Line Interface

```
usage: que [options] [file/to/require] ...
    -h, --help                       Show this help text.
    -i, --poll-interval [INTERVAL]   Set maximum interval between polls for available jobs, in seconds (default: 5)
    -l, --log-level [LEVEL]          Set level at which to log to STDOUT (debug, info, warn, error, fatal) (default: info)
    -p, --worker-priorities [LIST]   List of priorities to assign to workers (default: 10,30,50,any,any,any)
    -q, --queue-name [NAME]          Set a queue name to work jobs from. Can be passed multiple times. (default: the default queue only)
    -w, --worker-count [COUNT]       Set number of workers in process (default: 6)
    -v, --version                    Print Que version and exit.
        --connection-url [URL]       Set a custom database url to connect to for locking purposes.
        --log-internals              Log verbosely about Que's internal state. Only recommended for debugging issues
        --maximum-buffer-size [SIZE] Set maximum number of jobs to be locked and held in this process awaiting a worker (default: 8)
        --wait-period [PERIOD]       Set maximum interval between checks of the in-memory job queue, in milliseconds (default: 50)
```

Some explanation of the more unusual options:

### `worker-priorities` and `worker-count`

These options dictate the size and priority distribution of the worker pool. The default worker-priorities is `10,30,50,any,any,any`. This means that the default worker pool will reserve one worker to only works jobs with priorities under 10, one for priorities under 30, and one for priorities under 50. Three more workers will work any job.

For example, with these defaults, you could have a large backlog of jobs of priority 100. When a more important job (priority 40) comes in, there's guaranteed to be a free worker. If the process then becomes saturated with jobs of priority 40, and then a priority 20 job comes in, there's guaranteed to be a free worker for it, and so on. You can pass a priority more than once to have multiple workers at that level (for example: `--worker-priorities=100,100,any,any`). This gives you a lot of freedom to manage your worker capacity at different priority levels.

Instead of passing worker-priorities, you can pass a `worker-count` - this is a shorthand for creating the given number of workers at the `any` priority level. So, `--worker-count=3` is just like passing equivalent to `worker-priorities=any,any,any`.

If you pass both worker-count and worker-priorities, the count will trim or pad the priorities list with `any` workers. So, `--worker-priorities=20,30,40 --worker-count=6` would be the same as passing `--worker-priorities=20,30,40,any,any,any`.

### `poll-interval`

This option sets the number of seconds the process will wait between polls of the job queue. Jobs that are ready to be worked immediately will be broadcast via the LISTEN/NOTIFY system, so polling is unnecessary for them - polling is only necessary for jobs that are scheduled in the future or which are being delayed due to errors. The default is 5 seconds.

### `maximum-buffer-size`

This option sets the size of the internal buffer that Que uses to hold jobs until they're ready for workers. The default maximum is 8, meaning that the process won't buffer more than 8 jobs that aren't yet ready to be worked. If you don't want jobs to be buffered at all, you can set this value to zero.

### `connection-url`

This option sets the URL to be used to open a connection to the database for locking purposes. By default, Que will simply use a connection from the connection pool for locking - this option is only useful if your application connections can't use advisory locks - for example, if they're passed through an external connection pool like PgBouncer. In that case, you'll need to use this option to specify your actual database URL so that Que can establish a direct connection.

### `wait-period`

This option specifies (in milliseconds) how often the locking thread wakes up to check whether the workers have finished jobs, whether it's time to poll, etc. You shouldn't generally need to tweak this, but it may come in handy for some workloads. The default is 50 milliseconds.

### `log-internals`

This option instructs Que to output a lot of information about its internal state to the logger. It should only be used if it becomes necessary to debug issues.

## Advanced Setup

### Using ActiveRecord Without Rails

If you're using both Rails and ActiveRecord, the README describes how to get started with Que (which is pretty straightforward, since it includes a Railtie that handles a lot of setup for you). Otherwise, you'll need to do some manual setup.

If you're using ActiveRecord outside of Rails, you'll need to tell Que to piggyback on its connection pool after you've connected to the database:

```ruby
ActiveRecord::Base.establish_connection(ENV['DATABASE_URL'])

require 'que'
Que.connection = ActiveRecord
```

Then you can queue jobs just as you would in Rails:

```ruby
ActiveRecord::Base.transaction do
  @user = User.create(params[:user])
  SendRegistrationEmail.enqueue user_id: @user.id
end
```

There are other docs to read if you're using [Sequel](#using-sequel) or [plain Postgres connections](#using-plain-postgres-connections) (with no ORM at all) instead of ActiveRecord.

### Managing the Jobs Table

After you've connected Que to the database, you can manage the jobs table. You'll want to migrate to a specific version in a migration file, to ensure that they work the same way even when you upgrade Que in the future:

```ruby
# Update the schema to version #7.
Que.migrate!(version: 7)

# Remove Que's jobs table entirely.
Que.migrate!(version: 0)
```

There's also a helper method to clear all jobs from the jobs table:

```ruby
Que.clear!
```

### Other Setup

Be sure to read the docs on [managing workers](#managing-workers) for more information on using the worker pool.

You'll also want to set up [logging](#logging) and an [error handler](#error-handling) to track errors raised by jobs.

## Error Handling

If an error is raised and left uncaught by your job, Que will save the error message and backtrace to the database and schedule the job to be retried later.

If a given job fails repeatedly, Que will retry it at exponentially-increasing intervals equal to (failure_count^4 + 3) seconds. This means that a job will be retried 4 seconds after its first failure, 19 seconds after its second, 84 seconds after its third, 259 seconds after its fourth, and so on until it succeeds. This pattern is very similar to DelayedJob's. Alternately, you can define your own retry logic by setting an interval to delay each time, or a callable that accepts the number of failures and returns an interval:

```ruby
class MyJob < Que::Job
  # Just retry a failed job every 5 seconds:
  self.retry_interval = 5

  # Always retry this job immediately (not recommended, or transient
  # errors will spam your error reporting):
  self.retry_interval = 0

  # Increase the delay by 30 seconds every time this job fails:
  self.retry_interval = proc { |count| count * 30 }
end
```

There is a maximum_retry_count option for jobs. It defaults to 15 retries, which with the default retry interval means that a job will stop retrying after a little more than two days.

### Error Notifications

If you're using an error notification system (highly recommended, of course), you can hook Que into it by setting a callable as the error notifier:

```ruby
Que.error_notifier = proc do |error, job|
  # Do whatever you want with the error object or job row here. Note that the
  # job passed is not the actual job object, but the hash representing the job
  # row in the database, which looks like:

  # {
  #   :priority => 100,
  #   :run_at => "2017-09-15T20:18:52.018101Z",
  #   :id => 172340879,
  #   :job_class => "TestJob",
  #   :error_count => 0,
  #   :last_error_message => nil,
  #   :queue => "default",
  #   :last_error_backtrace => nil,
  #   :finished_at => nil,
  #   :expired_at => nil,
  #   :args => [],
  #   :data => {}
  # }

  # This is done because the job may not have been able to be deserialized
  # properly, if the name of the job class was changed or the job class isn't
  # loaded for some reason. The job argument may also be nil, if there was a
  # connection failure or something similar.
end
```

### Error-Specific Handling

You can also define a handle_error method in your job, like so:

```ruby
class MyJob < Que::Job
  def run(*args)
    # Your code goes here.
  end

  def handle_error(error)
    case error
    when TemporaryError then retry_in 10.seconds
    when PermanentError then expire
    else super # Default (exponential backoff) behavior.
    end
  end
end
```

The return value of handle_error determines whether the error object is passed to the error notifier. The helper methods like expire and retry_in return true, so these errors will be notified. You can explicitly return false to skip notification.

```ruby
class MyJob < Que::Job
  def handle_error(error)
    case error
    when AnnoyingError
      retry_in 10.seconds
      false
    when TransientError
      super
      error_count > 3
    else
      super # Default (exponential backoff) behavior.
    end
  end
end
```

In this example, AnnoyingError will never be notified, while TransientError will only be notified once it has affected a given job at least three times.

## Inspecting the Queue

In order to remain simple and compatible with any ORM (or no ORM at all), Que is really just a very thin wrapper around some raw SQL. There are two methods available that query the jobs table and Postgres' system catalogs to retrieve information on the current state of the queue:

### Job Stats

You can call `Que.job_stats` to return some aggregate data on the types of jobs currently in the queue. Example output:

```ruby
[
  {
    :job_class=>"ChargeCreditCard",
    :count=>10,
    :count_working=>4,
    :count_errored=>2,
    :highest_error_count=>5,
    :oldest_run_at=>2017-09-08 16:13:18 -0400
  },
  {
    :job_class=>"SendRegistrationEmail",
    :count=>1,
    :count_working=>0,
    :count_errored=>0,
    :highest_error_count=>0,
    :oldest_run_at=>2017-09-08 17:13:18 -0400
  }
]
```

This tells you that, for instance, there are ten ChargeCreditCard jobs in the queue, four of which are currently being worked, and two of which have experienced errors. One of them has started to process but experienced an error five times. The oldest_run_at is helpful for determining how long jobs have been sitting around, if you have a large backlog.

### Custom Queries

If you're using ActiveRecord or Sequel, Que ships with models that wrap the job queue so you can write your own logic to inspect it. They include some helpful scopes to write your queries - see the gem source for a complete accounting.

#### ActiveRecord Example

``` ruby
# app/models/que_job.rb

require 'que/active_record/model'

class QueJob < Que::ActiveRecord::Model
end

QueJob.finished.to_sql # => "SELECT \"que_jobs\".* FROM \"que_jobs\" WHERE (\"que_jobs\".\"finished_at\" IS NOT NULL)"

# You could also name the model whatever you like, or just query from
# Que::ActiveRecord::Model directly if you don't need to write your own model
# logic.
```

#### Sequel Example

``` ruby
# app/models/que_job.rb

require 'que/sequel/model'

class QueJob < Que::Sequel::Model
end

QueJob.finished # => #<Sequel::Postgres::Dataset: "SELECT * FROM \"public\".\"que_jobs\" WHERE (\"public\".\"que_jobs\".\"finished_at\" IS NOT NULL)">
```

## Managing Workers

Que uses a multithreaded pool of workers to run jobs in parallel - this allows you to save memory by working many jobs simultaneously in the same process. The `que` executable starts up a pool of 6 workers by default. This is fine for most use cases, but the ideal number for your app will depend on your interpreter and what types of jobs you're running.

Ruby MRI has a global interpreter lock (GIL), which prevents it from using more than one CPU core at a time. Having multiple workers running makes sense if your jobs tend to spend a lot of time in I/O (waiting on complex database queries, sending emails, making HTTP requests, etc.), as most jobs do. However, if your jobs are doing a lot of work in Ruby, they'll be spending a lot of time blocking each other, and having too many workers running will cause you to lose efficiency to context-switching. So, you'll want to choose the appropriate number of workers for your use case.

### Working Jobs Via Executable

```shell
# Run a pool of 6 workers:
que

# Or configure the number of workers:
que --worker-count 10
```

See `que -h` for a complete list of command-line options.

### Thread-Unsafe Application Code

If your application code is not thread-safe, you won't want any workers to be processing jobs while anything else is happening in the Ruby process. So, you'll want to run a single worker at a time, like so:

```shell
que --worker-count 1
```

## Logging

By default, Que logs important information in JSON to either Rails' logger (when running in a Rails web process) or STDOUT (when running via the `que` executable). So, your logs will look something like:

```
I, [2017-08-12T05:07:31.094201 #4687]  INFO -- : {"lib":"que","hostname":"lovelace","pid":98240,"thread":42660,"event":"job_worked","job":{"priority":1,"run_at":"2024-07-24T11:07:10.056514Z","id":2869885284504751564,"job_class":"WorkerJob","error_count":0,"last_error_message":null,"queue":"default","last_error_backtrace":null,"finished_at":null,"expired_at":null,"args":[1],"data":{},"job_schema_version":2,"kwargs":{}},"elapsed":0.001356}
```

Of course you can have it log wherever you like:

```ruby
Que.logger = Logger.new(...)
```

If you don't like logging in JSON, you can also customize the format of the logging output by passing a callable object (such as a proc) to Que.log_formatter=. The proc should take a hash (the keys are symbols) and return a string. The keys and values are just as you would expect from the JSON output:

```ruby
Que.log_formatter = proc do |data|
  "Thread number #{data[:thread]} experienced a #{data[:event]}"
end
```

If the log formatter returns nil or false, nothing will be logged at all. You could use this to narrow down what you want to emit, for example:

```ruby
Que.log_formatter = proc do |data|
  if [:job_worked, :job_unavailable].include?(data[:event])
    JSON.dump(data)
  end
end
```

### Logging Job Completion

Que logs a `job_worked` event whenever a job completes, though by default this event is logged at the `DEBUG` level. Since people often run their applications at the `INFO` level or above, this can make the logs too silent for some use cases. Similarly, you may want to log at a higher level if a time-sensitive job begins taking too long to run.

You can solve these problems by configuring the level at which a job is logged on a per-job basis. Simply define a `log_level` method in your job class - it will be called with a float representing the number of seconds it took for the job to run, and it should return a symbol indicating what level to log the job at:

```ruby
class TimeSensitiveJob < Que::Job
  def run(*args)
    RemoteAPI.execute_important_request
  end

  def log_level(elapsed)
    if elapsed > 60
      # This job took over a minute! We should complain about it!
      :warn
    elsif elapsed > 30
      # A little long, but no big deal!
      :info
    else
      # This is fine, don't bother logging at all.
      false
    end
  end
end
```

This method should return a symbol that is a valid logging level (one of `[:debug, :info, :warn, :error, :fatal, :unknown]`). If the method returns anything other than one of these symbols, the job won't be logged.

If a job errors, a `job_errored` event will be emitted at the `ERROR` log level. This is not currently configurable.

## Migrating

Some new releases of Que may require updates to the database schema. It's recommended that you integrate these updates alongside your other database migrations. For example, when Que released version 0.6.0, the schema version was updated from 2 to 3. If you're running ActiveRecord, you could make a migration to perform this upgrade like so:

```ruby
class UpdateQue < ActiveRecord::Migration[5.0]
  def self.up
    Que.migrate!(version: 3)
  end

  def self.down
    Que.migrate!(version: 2)
  end
end
```

This will make sure that your database schema stays consistent with your codebase. If you're looking for something quicker and dirtier, you can always manually migrate in a console session:

```ruby
# Change schema to version 3.
Que.migrate!(version: 3)

# Check your current schema version.
Que.db_version #=> 3
```

Note that you can remove Que from your database completely by migrating to version 0.

## Multiple Queues

Que supports the use of multiple queues in a single job table. Please note that this feature is intended to support the case where multiple codebases are sharing the same job queue - if you want to support jobs of differing priorities, the numeric priority system offers better flexibility and performance.

For instance, you might have a separate Ruby application that handles only processing credit cards. In that case, you can run that application's workers against a specific queue:

```shell
que --queue-name credit_cards
# The -q flag is equivalent, and either can be passed multiple times.
que -q default -q credit_cards
```

Then you can set jobs to be enqueued in that queue specifically:

```ruby
ProcessCreditCard.enqueue(current_user.id, job_options: { queue: 'credit_cards' })

# Or:

class ProcessCreditCard < Que::Job
  # Set a default queue for this job class; this can be overridden by
  # passing the :queue parameter to enqueue like above.
  self.queue = 'credit_cards'
end
```

In some cases, the `ProcessCreditCard` class may not be defined in the application that is enqueueing the job. In that case, you can [specify the job class as a string](#job_class).

## Shutting Down Safely

To ensure safe operation, Que needs to be very careful in how it shuts down. When a Ruby process ends normally, it calls Thread#kill on any threads that are still running - unfortunately, if a thread is in the middle of a transaction when this happens, there is a risk that it will be prematurely commited, resulting in data corruption. See [here](http://blog.headius.com/2008/02/ruby-threadraise-threadkill-timeoutrb.html) and [here](http://coderrr.wordpress.com/2011/05/03/beware-of-threadkill-or-your-activerecord-transactions-are-in-danger-of-being-partially-committed/) for more detail on this.

To prevent this, Que will block the worker process from exiting until all jobs it is working have completed normally. Unfortunately, if you have long-running jobs, this may take a very long time (and if something goes wrong with a job's logic, it may never happen). The solution in this case is SIGKILL - luckily, Ruby processes that are killed via SIGKILL will end without using Thread#kill on its running threads. This is safer than exiting normally - when PostgreSQL loses the connection it will simply roll back the open transaction, if any, and unlock the job so it can be retried later by another worker. Be sure to read [Writing Reliable Jobs](#writing-reliable-jobs) for information on how to design your jobs to fail safely.

So, be prepared to use SIGKILL on your Ruby processes if they run for too long. For example, Heroku takes a good approach to this - when Heroku's platform is shutting down a process, it sends SIGTERM, waits ten seconds, then sends SIGKILL if the process still hasn't exited. This is a nice compromise - it will give each of your currently running jobs ten seconds to complete, and any jobs that haven't finished by then will be interrupted and retried later.

## Using Plain Postgres Connections

If you're not using an ORM like ActiveRecord or Sequel, you can use a distinct connection pool to manage your Postgres connections. Please be aware that if you **are** using ActiveRecord or Sequel, there's no reason for you to be using any of these methods - it's less efficient (unnecessary connections will waste memory on your database server) and you lose the reliability benefits of wrapping jobs in the same transactions as the rest of your data.

### Using ConnectionPool or Pond

Support for two connection pool gems is included in Que. The first is the ConnectionPool gem (be sure to add `gem 'connection_pool'` to your Gemfile):

```ruby
require 'uri'
require 'pg'
require 'connection_pool'

uri = URI.parse(ENV['DATABASE_URL'])

Que.connection = ConnectionPool.new(size: 10) do
  PG::Connection.open(
    host:     uri.host,
    user:     uri.user,
    password: uri.password,
    port:     uri.port || 5432,
    dbname:   uri.path[1..-1]
  )end
```

Be sure to pick your pool size carefully - if you use 10 for the size, you'll incur the overhead of having 10 connections open to Postgres even if you never use more than a couple of them.

The Pond gem doesn't have this drawback - it is very similar to ConnectionPool, but establishes connections lazily (add `gem 'pond'` to your Gemfile):

```ruby
require 'uri'
require 'pg'
require 'pond'

uri = URI.parse(ENV['DATABASE_URL'])

Que.connection = Pond.new(maximum_size: 10) do
  PG::Connection.open(
    host:     uri.host,
    user:     uri.user,
    password: uri.password,
    port:     uri.port || 5432,
    dbname:   uri.path[1..-1]
  )
end
```

### Using Any Other Connection Pool

You can use any other in-process connection pool by defining access to it in a proc that's passed to `Que.connection_proc = proc`. The proc you pass should accept a block and call it with a connection object. For instance, Que's built-in interface to Sequel's connection pool is basically implemented like:

```ruby
Que.connection_proc = proc do |&block|
  DB.synchronize do |connection|
    block.call(connection)
  end
end
```

This proc must meet a few requirements:
- The yielded object must be an instance of `PG::Connection`.
- It must be reentrant - if it is called with a block, and then called again inside that block, it must return the same object. For example, in `proc.call{|conn1| proc.call{|conn2| conn1.object_id == conn2.object_id}}` the innermost condition must be true.
- It must lock the connection object and prevent any other thread from accessing it for the duration of the block.

If any of these conditions aren't met, Que will raise an error.

## Using Sequel

If you're using Sequel, with or without Rails, you'll need to give Que a specific database instance to use:

```ruby
DB = Sequel.connect(ENV['DATABASE_URL'])
Que.connection = DB
```

If you are using Sequel's migrator, your app initialization won't happen, so you may need to tweak your migrations to `require 'que'` and set its connection:

```ruby
require 'que'
Sequel.migration do
  up do
    Que.connection = self
    Que.migrate!(version: 7)
  end
  down do
    Que.connection = self
    Que.migrate!(version: 0)
  end
end
```

Then you can safely use the same database object to transactionally protect your jobs:

```ruby
class MyJob < Que::Job
  def run(user_id:)
    # Do stuff.

    DB.transaction do
      # Make changes to the database.

      # Destroying this job will be protected by the same transaction.
      destroy
    end
  end
end

# Or, in your controller action:
DB.transaction do
  @user = User.create(params[:user])
  MyJob.enqueue user_id: @user.id
end
```

Sequel automatically wraps model persistance actions (create, update, destroy) in transactions, so you can simply call #enqueue methods from your models' callbacks, if you wish.

## Using Que With ActiveJob

You can include `Que::ActiveJob::JobExtensions` into your `ApplicationJob` subclass to get support for all of Que's
[helper methods](#job-helper-methods). These methods will become no-ops if you use a queue adapter that isn't Que, so if you like to use a different adapter in development they shouldn't interfere.

Additionally, including `Que::ActiveJob::JobExtensions` lets you define a run() method that supports keyword arguments.

## Job Helper Methods

There are a number of instance methods on Que::Job that you can use in your jobs, preferably in transactions. See [Writing Reliable Jobs](#writing-reliable-jobs) for more information on where to use these methods.

### `destroy`

This method deletes the job from the queue table, ensuring that it won't be worked a second time.

### `finish`

This method marks the current job as finished, ensuring that it won't be worked a second time. This is like destroy, in that it finalizes a job, but this method leaves the job in the table, in case you want to query it later.

### `expire`

This method marks the current job as expired. It will be left in the table and won't be retried, but it will be easy to query for expired jobs. This method is called if the job exceeds its maximum_retry_count.

### `retry_in`

This method marks the current job to be retried later. You can pass a numeric to this method, in which case that is the number of seconds after which it can be retried (`retry_in(10)`, `retry_in(0.5)`), or, if you're using ActiveSupport, you can pass in a duration object (`retry_in(10.minutes)`). This automatically happens, with an exponentially-increasing interval, when the job encounters an error.

Note that `retry_in` increments the job's `error_count`.

### `error_count`

This method returns the total number of times the job has errored, in case you want to modify the job's behavior after it has failed a given number of times.

### `default_resolve_action`

If you don't perform a resolve action (destroy, finish, expire, retry_in) while the job is worked, Que will call this method for you. By default it simply calls `destroy`, but you can override it in your Job subclasses if you wish - for example, to call `finish`, or to invoke some more complicated logic.

## Writing Reliable Jobs

Que does everything it can to ensure that jobs are worked exactly once, but if something bad happens when a job is halfway completed, there's no way around it - the job will need be repeated over again from the beginning, probably by a different worker. When you're writing jobs, you need to be prepared for this to happen.

The safest type of job is one that reads in data, either from the database or from external APIs, then does some number crunching and writes the results to the database. These jobs are easy to make safe - simply write the results to the database inside a transaction, and also destroy the job inside that transaction, like so:

```ruby
class UpdateWidgetPrice < Que::Job
  def run(widget_id)
    widget = Widget[widget_id]
    price  = ExternalService.get_widget_price(widget_id)

    ActiveRecord::Base.transaction do
      # Make changes to the database.
      widget.update price: price

      # Mark the job as destroyed, so it doesn't run again.
      destroy
    end
  end
end
```

Here, you're taking advantage of the guarantees of an [ACID](https://en.wikipedia.org/wiki/ACID) database. The job is destroyed along with the other changes, so either the write will succeed and the job will be run only once, or it will fail and the database will be left untouched. But even if it fails, the job can simply be retried, and there are no lingering effects from the first attempt, so no big deal.

The more difficult type of job is one that makes changes that can't be controlled transactionally. For example, writing to an external service:

```ruby
class ChargeCreditCard < Que::Job
  def run(user_id, credit_card_id)
    CreditCardService.charge(credit_card_id, amount: "$10.00")

    ActiveRecord::Base.transaction do
      User.where(id: user_id).update_all charged_at: Time.now
      destroy
    end
  end
end
```

What if the process abruptly dies after we tell the provider to charge the credit card, but before we finish the transaction? Que will retry the job, but there's no way to tell where (or even if) it failed the first time. The credit card will be charged a second time, and then you've got an angry customer. The ideal solution in this case is to make the job [idempotent](https://en.wikipedia.org/wiki/Idempotence), meaning that it will have the same effect no matter how many times it is run:

```ruby
class ChargeCreditCard < Que::Job
  def run(user_id, credit_card_id)
    unless CreditCardService.check_for_previous_charge(credit_card_id)
      CreditCardService.charge(credit_card_id, amount: "$10.00")
    end

    ActiveRecord::Base.transaction do
      User.where(id: user_id).update_all charged_at: Time.now
      destroy
    end
  end
end
```

This makes the job slightly more complex, but reliable (or, at least, as reliable as your credit card service).

Finally, there are some jobs where you won't want to write to the database at all:

```ruby
class SendVerificationEmail < Que::Job
  def run(email_address)
    Mailer.verification_email(email_address).deliver
  end
end
```

In this case, we don't have a way to prevent the occasional double-sending of an email. But, for ease of use, you can leave out the transaction and the `destroy` call entirely - Que will recognize that the job wasn't destroyed and will clean it up for you.

### Timeouts

Long-running jobs aren't necessarily a problem for the database, since the overhead of an individual job is very small (just an advisory lock held in memory). But jobs that hang indefinitely can tie up a worker and [block the Ruby process from exiting gracefully](#shutting-down-safely), which is a pain.

If there's part of your job that is prone to hang (due to an API call or other HTTP request that never returns, for example), you can (and should) timeout those parts of your job. For example, consider a job that needs to make an HTTP request and then write to the database:

```ruby
class ScrapeStuff < Que::Job
  def run(url_to_scrape)
    result = YourHTTPLibrary.get(url_to_scrape)

    ActiveRecord::Base.transaction do
      # Insert result...

      destroy
    end
  end
end
```

That request could take a very long time, or never return at all. Let's use the timeout feature that almost all HTTP libraries offer some version of:

```ruby
class ScrapeStuff < Que::Job
  def run(url_to_scrape)
    result = YourHTTPLibrary.get(url_to_scrape, timeout: 5)

    ActiveRecord::Base.transaction do
      # Insert result...

      destroy
    end
  end
end
```

Now, if the request takes more than five seconds, an error will be raised (probably - check your library's documentation) and Que will just retry the job later.

## Job Options

When enqueueing a job, you can specify particular options for it in a `job_options` hash, e.g.:

```ruby
ChargeCreditCard.enqueue(card.id, user_id: current_user.id, job_options: { run_at: 1.day.from_now, priority: 5 })
```

### `queue`

See [Multiple Queues](#multiple-queues).

### `priority`

Provide an integer to customise the priority level of the job.

We use the Linux priority scale - a lower number is more important.

### `run_at`

Provide a `Time` as the `run_at` to make a job run at a later time (well, at some point after it, depending on how busy the workers are).

It's best not to use `Time.now` here, as the current time in the Ruby process and the database won't be perfectly aligned. When the database considers the `run_at` to be in the past, the job will not be broadcast via the LISTEN/NOTIFY system, and it will need to wait for a poll. This introduces an unnecessary delay of probably a few seconds (depending on your configured [poll interval](#poll-interval)). So if you want the job to run ASAP, just omit the `run_at` option.

### `job_class`

Specifying `job_class` allows you to enqueue a job using `Que.enqueue`:

```ruby
Que.enqueue(current_user.id, job_options: { job_class: 'ProcessCreditCard' })
```

Rather than needing to use the job class (nor even have it defined in the enqueueing process):

```ruby
ProcessCreditCard.enqueue(current_user.id)
```

### `tags`

You can provide an array of strings to give a job some tags. These are not used by Que and are completely custom.

A job can have up to five tags, each one up to 100 characters long.

Note that unlike the other job options, tags are stored within the `que_jobs.data` column, rather than a correspondingly-named column.

## Middleware

A new feature in 1.0 is support for custom middleware around various actions.

This API is experimental for the 1.0 beta and may change.

### Defining Middleware For Jobs

You can define middleware to wrap worked jobs. You can use this to add custom instrumentation around jobs, log how long they take to complete, etc.

``` ruby
Que.job_middleware.push(
  -> (job, &block) {
    # Do stuff with the job object - report on it, count time elapsed, etc.
    block.call
    nil # Doesn't matter what's returned.
  }
)
```

### Defining Middleware For SQL statements

SQL middleware wraps queries that Que executes, or which you might decide to execute via Que.execute(). You can use hook this into NewRelic or a similar service to instrument how long SQL queries take, for example.

``` ruby
Que.sql_middleware.push(
  -> (sql, params, &block) {
    Service.instrument(sql: sql, params: params) do
      block.call
    end
    nil # Still doesn't matter what's returned.
  }
)
```

Please be careful with what you do inside an SQL middleware - this code will execute inside Que's locking thread, which runs in a fairly tight loop that is optimized for performance. If you do something inside this block that incurs blocking I/O (like synchronously touching an external service) you may find Que being less able to pick up jobs quickly.

## Vacuuming

Because the que_jobs table is "high churn" (lots of rows are being created and deleted), it needs to be vacuumed fairly frequently to keep the dead tuple count down otherwise [acquring a job to work will start taking longer and longer](https://brandur.org/postgres-queues).

In many cases postgres will vacuum these dead tuples automatically using autovacuum, so no intervention is required. However, if your database has a lot of other large tables that take hours for autovacuum to run on, it is possible that there won't be any autovacuum processes available within a reasonable amount of time. If that happens the dead tuple count on the que_jobs table will reach a point where it starts taking so long to acquire a job to work that the jobs are being added faster than they can be worked.

In order to avoid this situation you can kick off a manual vacuum against the que_jobs table on a regular basis. This manual vacuum will be more aggressive than an autovacuum since by default it does not back-off and sleep, so you will want to make sure your server has enough disk I/O available to handle the vacuum + any autovacuums + your workload + some overhead. However, by keeping the interval between vacuums small you will also be limiting the amount of work to be done which will aleviate some of the afforementiond risk of I/O usage.

Here is an example recurring manual vacuum job that assumes you are using Sequel:

```
class ManualVacuumJob < CronJob
  self.priority = 1 # set this to the highest priority since it keeps the table healthy for other jobs
  INTERVAL = 300

  def run(args)
    DB.run "VACUUM VERBOSE ANALYZE que_jobs"
  end
end
```

## Enqueueing jobs in bulk

If you need to enqueue a large number of jobs at once, enqueueing each one separately (and running the notify trigger for each) can become a performance bottleneck. To mitigate this, there is a bulk enqueue interface:

```ruby
Que.bulk_enqueue do
  MyJob.enqueue(user_id: 1)
  MyJob.enqueue(user_id: 2)
  # ...
end
```

The jobs are only actually enqueued at the end of the block, at which point they are inserted into the database in one big query.

Limitations:

- ActiveJob is not supported
- All jobs must use the same job class
- All jobs must use the same `job_options` (`job_options` must be provided to `.bulk_enqueue` instead of `.enqueue`)
- The `que_attrs` of a job instance returned from `.enqueue` is empty (`{}`)
- The notify trigger is not run by default, so jobs will only be picked up by a worker upon its next poll

If you still want the notify trigger to run for each job, use `Que.bulk_enqueue(notify: true) { ... }`.

## Expired jobs

Expired jobs hang around in the `que_jobs` table. If necessary, you can get an expired job to run again by clearing the `error_count` and `expired_at` columns, e.g.:

```sql
UPDATE que_jobs SET error_count = 0, expired_at = NULL WHERE id = 172340879;
```

## Finished jobs

If you prefer to leave finished jobs in the database for a while, to performantly remove them periodically, you can use something like:

```sql
BEGIN;
SET LOCAL que.skip_notify TO true;
DELETE FROM que_jobs WHERE finished_at < (select now() - interval '7 days');
COMMIT;
```
