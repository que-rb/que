## Error Handling

If an error is raised and left uncaught by your job, Que will save the error message and backtrace to the database and schedule the job to be retried later.

If a given job fails repeatedly, Que will retry it at exponentially-increasing intervals equal to (failure_count[^4^] + 3) seconds. This means that a job will be retried 4 seconds after its first failure, 19 seconds after its second, 84 seconds after its third, 259 seconds after its fourth, and so on until it succeeds. This pattern is very similar to DelayedJob's.

Unlike DelayedJob, however, there is currently no maximum number of failures after which jobs will be deleted. Que's assumption is that if a job is erroring perpetually (and not just transiently), you will want to take action to get the job working properly rather than simply losing it silently.

If you're using an error notification system (highly recommended, of course), you can hook Que into it by setting a callable as the error handler:

    Que.error_handler = proc do |error|
      # Do whatever you want with the error object.
    end

    # Or, in your Rails configuration:

    config.que.error_handler = proc { |error| ... }
