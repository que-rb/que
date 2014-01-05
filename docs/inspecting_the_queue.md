## Inspecting the Queue

In order to remain simple and compatible with any ORM (or no ORM at all), Que is really just a very thin wrapper around some raw SQL. There are two methods available that query the jobs table and Postgres' system catalogs to retrieve information on the current state of the queue:

### Job Stats

You can call `Que.job_stats` to return some aggregate data on the types of jobs currently in the queue. Example output:

    [
      {
        "job_class"=>"ChargeCreditCard",
        "count"=>"10",
        "count_working"=>"4",
        "count_errored"=>"2",
        "highest_error_count"=>"5",
        "oldest_run_at"=>"2014-01-04 21:24:55.817129+00"
      },
      {
        "job_class"=>"SendRegistrationEmail",
        "count"=>"8",
        "count_working"=>"0",
        "count_errored"=>"0",
        "highest_error_count"=>"0",
        "oldest_run_at"=>"2014-01-04 22:24:55.81532+00"
      }
    ]

This tells you that, for instance, there are ten ChargeCreditCard jobs in the queue, four of which are currently being worked, and two of which have experienced errors. One of them has started to process but experienced an error five times. The oldest_run_at is helpful for determining how long jobs have been sitting around, if you have backlog.

### Worker States

You can call `Que.worker_states` to return some information on every worker touching the queue (not just those in the current process). Example output:

    [
      {
        "priority"=>"2",
        "run_at"=>"2014-01-04 22:35:55.772324+00",
        "job_id"=>"4592",
        "job_class"=>"ChargeCreditCard",
        "args"=>"[345,56]",
        "error_count"=>"0",
        "last_error"=>nil,
        "pg_backend_pid"=>"1175",
        "pg_state"=>"idle",
        "pg_state_changed_at"=>"2014-01-04 22:35:55.777785+00",
        "pg_last_query"=>"SELECT * FROM users",
        "pg_last_query_started_at"=>"2014-01-04 22:35:55.777519+00",
        "pg_transaction_started_at"=>nil,
        "pg_waiting_on_lock"=>"f"
      }
    ]

In this case, there is only one worker currently working the queue. The first seven fields are the attributes of the job it is currently running. The next seven fields are information about that worker's Postgres connection, and are taken from `pg_stat_activity` - see [Postgres' documentation](http://www.postgresql.org/docs/current/static/monitoring-stats.html#PG-STAT-ACTIVITY-VIEW) for more information on interpreting these fields.

* `pg_backend_pid` - The pid of the Postgres process serving this worker. This is useful if you wanted to kill that worker's connection, for example, by running "SELECT pg_terminate_backend(1175)". This would free up the job to be attempted by another worker.
* `pg_state` - The state of the Postgres backend. It may be "active" if the worker is currently running a query or "idle"/"idle in transaction" if it is not. It may also be in one of a few other less common states.
* `pg_state_changed_at` - The timestamp for when the backend's state was last changed. If the backend is idle, this would reflect the time that the last query finished.
* `pg_last_query` - The text of the current or most recent query that the worker sent to the database.
* `pg_last_query_started_at` - The timestamp for when the last query began to run.
* `pg_transaction_started_at` - The timestamp for when the worker's current transaction (if any) began.
* `pg_waiting_on_lock` - Whether or not the worker is waiting for a lock in Postgres to be released.

### Custom Queries

If you want to query the jobs table yourself to see what's been queued or to check the state of various jobs, you can always use Que to execute whatever SQL you want:

    Que.execute("select count(*) from que_jobs") #=> [{"count"=>"492"}]

If you want to use ActiveRecord's features when querying, you can define your own model around Que's job table:

    class QueJob < ActiveRecord::Base
    end

    # Or:

    class MyJob < ActiveRecord::Base
      self.table_name = :que_jobs
    end

Then you can query just as you would with any other model. Since the jobs table has a composite primary key, however, you probably won't be able to update or destroy jobs this way, though.

If you're using Sequel, you can use the same technique:

    class QueJob < Sequel::Model
    end

    # Or:

    class MyJob < Sequel::Model(:que_jobs)
    end

And note that Sequel *does* support composite primary keys:

    job = QueJob.where(:job_class => "ChargeCreditCard").first
    job.priority = 1
    job.save

Or, you can just use Sequel's dataset methods:

    DB[:que_jobs].where{priority > 3}.all
