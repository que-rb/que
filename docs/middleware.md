## Middleware

A new feature in 1.0 is support for custom middleware around various actions.

This API is experimental for the 1.0 beta and may change.

### Defining Middleware For Jobs

You can define middleware to wrap worked jobs. You can use this to add custom instrumentation around jobs, log how long they take to complete, etc.

``` ruby
Que.job_middleware.push(
  -> (job, &block) {
    # Do stuff with the job object - report on it, count time elapsed, etc.
    block.call
    nil # Doesn't matter what's returned.
  }
)
```

### Defining Middleware For SQL statements

SQL middleware wraps queries that Que executes, or which you might decide to execute via Que.execute(). You can use hook this into NewRelic or a similar service to instrument how long SQL queries take, for example.

``` ruby
Que.sql_middleware.push(
  -> (sql, params, &block) {
    Service.instrument(sql: sql, params: params) do
      block.call
    end
    nil # Still doesn't matter what's returned.
  }
)
```

Please be careful with what you do inside an SQL middleware - this code will execute inside Que's locking thread, which runs in a fairly tight loop that is optimized for performance. If you do something inside this block that incurs blocking I/O (like synchronously touching an external service) you may find Que being less able to pick up jobs quickly.
