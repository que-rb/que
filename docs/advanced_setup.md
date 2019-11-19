## Advanced Setup

### Using ActiveRecord Without Rails

If you're using both Rails and ActiveRecord, the README describes how to get started with Que (which is pretty straightforward, since it includes a Railtie that handles a lot of setup for you). Otherwise, you'll need to do some manual setup.

If you're using ActiveRecord outside of Rails, you'll need to tell Que to piggyback on its connection pool after you've connected to the database:

```ruby
ActiveRecord::Base.establish_connection(ENV['DATABASE_URL'])

require 'que'
Que.connection = ActiveRecord
```

Then you can queue jobs just as you would in Rails:

```ruby
ActiveRecord::Base.transaction do
  @user = User.create(params[:user])
  SendRegistrationEmail.enqueue user_id: @user.id
end
```

There are other docs to read if you're using [Sequel](https://github.com/que-rb/que/blob/master/docs/using_sequel.md) or [plain Postgres connections](https://github.com/que-rb/que/blob/master/docs/using_plain_connections.md) (with no ORM at all) instead of ActiveRecord.

### Managing the Jobs Table

After you've connected Que to the database, you can manage the jobs table. You'll want to migrate to a specific version in a migration file, to ensure that they work the same way even when you upgrade Que in the future:

```ruby
# Update the schema to version #4.
Que.migrate! version: 4

# Remove Que's jobs table entirely.
Que.migrate! version: 0
```

There's also a helper method to clear all jobs from the jobs table:

```ruby
Que.clear!
```

### Other Setup

Be sure to read the docs on [managing workers](https://github.com/que-rb/que/blob/master/docs/managing_workers.md) for more information on using the worker pool.

You'll also want to set up [logging](https://github.com/que-rb/que/blob/master/docs/logging.md) and an [error handler](https://github.com/que-rb/que/blob/master/docs/error_handling.md) to track errors raised by jobs.
