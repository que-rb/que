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
