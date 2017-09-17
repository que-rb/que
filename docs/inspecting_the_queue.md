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

(Write about the built-in models for ActiveRecord and Sequel)
