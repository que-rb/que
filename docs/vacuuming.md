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
