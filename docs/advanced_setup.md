## Advanced Setup

If you're using both Rails and ActiveRecord, the README describes how to get started with Que (which is pretty straightforward, since Que includes a Railtie that handles a lot of setup for you). Otherwise, you'll need to do some manual setup.

If you're using ActiveRecord outside of Rails, you'll need to tell Que to piggyback on its connection pool after you've connected to the database:

    ActiveRecord::Base.establish_connection(ENV['DATABASE_URL'])

    require 'que'
    Que.connection = ActiveRecord

Then you can queue jobs just as you would in Rails:

    ActiveRecord::Base.transaction do
      @user = User.create(params[:user])
      SendRegistrationEmail.enqueue user_id: @user.id
    end

There are other docs to read if you're using [Sequel](https://github.com/chanks/que/blob/master/docs/using_sequel.md) or [plain Postgres connections](https://github.com/chanks/que/blob/master/docs/using_plain_connections.md) (with no ORM at all) instead of ActiveRecord.

### Forking Servers

If you want to run a worker pool in your web process and you're using a forking webserver like Phusion Passenger (in smart spawning mode), Unicorn or Puma in some configurations, you'll want to set `Que.mode = :off` in your application configuration and only start up the worker pool in the child processes after the DB connection has been reestablished. So, for Puma:

    # config/puma.rb
    on_worker_boot do
      ActiveRecord::Base.establish_connection

      Que.mode = :async
    end

And for Unicorn:

    # config/unicorn.rb
    after_fork do |server, worker|
      ActiveRecord::Base.establish_connection

      Que.mode = :async
    end

And for Phusion Passenger:

    # config.ru
    if defined?(PhusionPassenger)
      PhusionPassenger.on_event(:starting_worker_process) do |forked|
        if forked
          Que.mode = :async
        end
      end
    end


### Managing the Jobs Table

After you've connected Que to the database, you can manage the jobs table:

    # Create/update the jobs table to the latest schema version:
    Que.migrate!

You'll want to migrate to a specific version if you're using migration files, to ensure that they work the same way even when you upgrade Que in the future:

    # Update the schema to version #3.
    Que.migrate! version: 3

    # To reverse the migration, drop the jobs table entirely:
    Que.migrate! version: 0

There's also a helper method to clear all jobs from the jobs table:

    Que.clear!

### Other Setup

You'll need to set Que's mode manually:

    # Start the worker pool:
    Que.mode = :async

    # Or, when testing:
    Que.mode = :sync

Be sure to read the docs on [managing workers](https://github.com/chanks/que/blob/master/docs/managing_workers.md) for more information on using the worker pool.

You'll also want to set up [logging](https://github.com/chanks/que/blob/master/docs/logging.md) and an [error handler](https://github.com/chanks/que/blob/master/docs/error_handling.md) to track errors raised by jobs.
