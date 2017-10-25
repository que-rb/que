## Defining Middleware For Jobs

You can define middleware to wrap jobs. For example:

``` ruby
Que.middleware.push(
  -> (job, &block) {
    # Do stuff with the job object - report on it, count time elapsed, etc.
    block.call
    nil # Doesn't matter what's returned.
  }
)
```

This API is experimental for the 1.0 beta and may change.
