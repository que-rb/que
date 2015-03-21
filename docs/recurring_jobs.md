### Recurring Jobs

As of 1.0, Que comes with built-in support for reliable recurring jobs. For an example, let's look at a job that runs once an hour and emails all users that have been created since the last run.

class EmailNewUsersJob < Que::RecurringJob
  # The interval after which the job will be repeated, in seconds. Can be
  # overridden in subclasses. Can use 1.hour if using Rails.

  @interval = 3600

  def run(account_id)
    start_time
    end_time
    time_range # start_time...end_time
    next_run_time

    users = User.where(created_at: time_range).to_a

    users.each { |user| user.email! }

    transaction do
      users.each { |user| user.update emailed_at: Time.now }
      reenqueue
    end
  end
end

In the same way that standard jobs destroy themselves after finishing without error if you haven't destroyed them, recurring jobs reenqueue themselves. You can also call destroy if you want a recurring job to stop itself at some point.

You can override the interval to the next job by passing an interval option to reenqueue.

Note that in order for these jobs to work, you must have a job table with a run_at column.

Que's support for scheduling jobs makes it easy to implement reliable recurring jobs. For example, suppose you want to run a job every hour that processes the users created in that time:

The same arguments hash will be passed to the recurring job each time it runs, unless you specify a new args hash like reenqueue args: [1, 'a', {blah: 'hello'}]. In our example above, you might use account_id to have different jobs email users that belong to different accounts, for example. This would let you process users in different accounts simultaneously.

Don't forget that after defining the recurring job you'll need to enqueue it for the first time. You can do so just as you'd enqueue any job, like EmailNewUsersJob.enqueue(78).

(Need to track times in args so that being delayed by errors doesn't affect the run_at. Need to track both start and end times in case they change the @interval.)

What are the benefits of using RecurringJob? There are several:

- Instead of using 1.hour.ago..Time.now in our database query, and requeueing the job at 1.hour.from_now, we use job arguments to track start and end times. This lets us correct for delays in running the job. Suppose that there's a backlog of priority jobs, or that the worker briefly goes down, and this job, which was supposed to run at 11:00 a.m. isn't run until 11:05 a.m. A lazier implementation would look for users created after 1.hour.ago, and miss those that signed up between 10:00 a.m. and 10:05 a.m.

This also compensates for clock drift. `Time.now` on one of your application servers may not match `Time.now` on another application server, which in turn may not match `now()` on your database server. The best way to stay reliable is have a single authoritative source on what the current time is, and your best source for authoritative information is always your database (this is why Que uses Postgres' `now()` function when locking jobs, by the way).

Note also the use of the triple-dot range, which results in a query like `SELECT "users".* FROM "users" WHERE ("users"."created_at" >= '2014-01-08 10:00:00.000000' AND "users"."created_at" < '2014-01-08 11:00:00.000000')` instead of a BETWEEN condition. This ensures that a user created at 11:00 am exactly isn't processed twice, by the jobs starting at both 10 am and 11 am.
