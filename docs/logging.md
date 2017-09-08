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
