## Logging

By default, Que logs important information in JSON to either Rails' logger (when running in a Rails web process) or STDOUT (when running via the `que` executable). So, your logs will look something like:

```
I, [2017-08-12T05:07:31.094201 #4687]  INFO -- : {"lib":"que","hostname":"lovelace","pid":21626,"thread":21471100,"event":"job_worked","job_id":6157665,"elapsed":0.531411}
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

## Logging Job Completion

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
