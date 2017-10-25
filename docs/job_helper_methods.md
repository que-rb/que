## Job Helper Methods

There are a number of instance methods on Que::Job that you can use in your jobs, preferably in transactions. See [Writing Reliable Jobs](/writing_reliable_jobs.md) for more information on where to use these methods.

### destroy

This method removes the job from the queue, ensuring that it won't be worked a second time.

### finish

This method marks the current job as finished

### expire

### retry_in

### handle_error(error)

### error_count

### default_resolve_action
