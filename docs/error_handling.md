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

TODO: Note that you can use handle_error to finish/destroy the job, or to manually set the retry delay depending on whatever conditions.

There is a maximum_retry_count option for jobs. It defaults to 15 retries, which with the default retry interval means that a job will stop retrying after a little more than two days.

## Error Notifications

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
  #   :data => {:args => [], :tags => []}
  # }

  # This is done because the job may not have been able to be deserialized
  # properly, if the name of the job class was changed or the job class isn't
  # loaded for some reason. The job argument may also be nil, if there was a
  # connection failure or something similar.
end
```
