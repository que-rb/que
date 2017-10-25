## Job Helper Methods

There are a number of instance methods on Que::Job that you can use in your jobs, preferably in transactions. See [Writing Reliable Jobs](/writing_reliable_jobs.md) for more information on where to use these methods.

### destroy

This method deletes the job from the queue table, ensuring that it won't be worked a second time.

### finish

This method marks the current job as finished, ensuring that it won't be worked a second time. This is like destroy, in that it finalizes a job, but this method leaves the job in the table, in case you want to query it later.

### expire

This method marks the current job as expired. It will be left in the table and won't be retried, but it will be easy to query for expired jobs. This method is called if the job exceeds its maximum_retry_count.

### retry_in

This method marks the current job to be retried later. You can pass a numeric to this method, in which case that is the number of seconds after which it can be retried (`retry_in(10)`, `retry_in(0.5)`), or, if you're using ActiveSupport, you can pass in a duration object (`retry_in(10.minutes)`). This automatically happens, with an exponentially-increasing interval, when the job encounters an error.

### error_count

This method returns the total number of times the job has errored, in case you want to modify the job's behavior after it has failed a given number of times.

### default_resolve_action

If you don't perform a resolve action (destroy, finish, expire, retry_in) while the job is worked, Que will call this method for you. By default it simply calls `destroy`, but you can override it in your Job subclasses if you wish - for example, to call `finish`, or to invoke some more complicated logic.
