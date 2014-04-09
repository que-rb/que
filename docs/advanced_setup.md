## Advanced Setup

If you're using both Rails and ActiveRecord, the README describes how to get started (which is pretty straightforward, since Que includes a Railtie that handles a lot of setup for you). Otherwise, you'll need to do some manual setup, the most important part of which is to hook Que into whatever connection pool you're already using so that your jobs can be transactionally protected.

##### ActiveRecord (Outside of Rails)

You'll need to tell Que to piggyback on ActiveRecord's connection pool, like so:

    Que.connection = ActiveRecord

With this setup you can safely use transaction blocks just as you typically would:

    ActiveRecord::Base.transaction do
      @user = User.create(params[:user])
      SendRegistrationEmail.enqueue :user_id => @user.id
    end

##### Sequel

If you're using Sequel, simply give Que the database object you're using:

    DB = Sequel.connect(ENV['DATABASE_URL'])
    Que.connection = DB

Then you can safely use the same database object to transactionally protect your jobs, similar to how you would with ActiveRecord:

    class MyJob < Que::Job
      def run
        # Do stuff.

        DB.transaction do
          # Make changes to the database.

          # Destroy this job atomically with other changes.
          destroy
        end
      end
    end

    # In your controller action:
    DB.transaction do
      @user = User.create(params[:user])
      MyJob.queue :user_id => @user.id
    end

##### ConnectionPool

If you don't feel the need to use a full database library, you can use the [ConnectionPool gem](https://github.com/mperham/connection_pool). ConnectionPool instances offer a `with` method that Que can use:

    require 'uri'
    require 'pg'
    require 'connection_pool'

    uri = URI.parse(ENV['DATABASE_URL'])

    pool = ConnectionPool.new :size => 10 do
      PG::Connection.open :host     => uri.host,
                          :user     => uri.user,
                          :password => uri.password,
                          :port     => uri.port || 5432,
                          :dbname   => uri.path[1..-1]
    end

    Que.connection = pool

Be sure to pick your pool size carefully - if you use 10 for the size, you'll incur the overhead of having 10 connections open to Postgres even if you never use more than a couple of them.

Also, please be aware that if you're using ActiveRecord or Sequel or another database library to manage your data, there's no benefit in setting up a separate connection pool for Que to use - it's less efficient (unnecessary connections will waste memory on your database server) and you lose the reliability benefits of wrapping jobs in the same transactions as the rest of your data.

##### Pond

[Pond](https://github.com/chanks/pond) is a pooling gem that is very similar to ConnectionPool, but establishes connections lazily, which is generally preferable as each Postgres connection has significant overhead.

    require 'uri'
    require 'pg'
    require 'pond'

    uri = URI.parse(ENV['DATABASE_URL'])

    pond = Pond.new :maximum_size => 10 do
      PG::Connection.open :host     => uri.host,
                          :user     => uri.user,
                          :password => uri.password,
                          :port     => uri.port || 5432,
                          :dbname   => uri.path[1..-1]
    end

    Que.connection = pond

##### Other Connection Pools

If you're using an ORM or other database library not covered here, Que can probably work with it without too much issue, you'll just need to give Que a proc (or other callable object) it can use to get a connection. The proc can contain any logic you like, so long as it is thread-safe, yields a PG::Connection object, and is [reentrant](https://en.wikipedia.org/wiki/Reentrancy_(computing)). Reentrancy means that, for the proc you give Que, the following must print true:

    connection_proc = proc do |&block|
      # Your logic here, which safely locks a PG::Connection and passes it to block.call()
    end

    connection_proc.call do |o1|
      connection_proc.call do |o2|
        puts o1 == o2 # Should be true.
      end
    end

As an example of how this works, consider the proc that Que uses internally to support ActiveRecord:

    Que.connection_proc = proc do |&block|
      ActiveRecord::Base.connection_pool.with_connection do |conn|
        # We let ActiveRecord's own connection pool handle the locking, but
        # #with_connection locks a connection adapter, so we still need to
        # call #raw_connection to get the actual PG::Connection object. Then
        # we just pass it to the block.

        block.call(conn.raw_connection)
      end
    end

If you have any trouble getting another type of connection pool working with Que, feel free to open an issue and ask for help.

### Forking Servers

If you want to run a worker pool in your web process and you're using a forking webserver like Unicorn or Puma in some configurations, you'll want to set `Que.mode = :off` in your application configuration and only start up the worker pool in the child processes. So, for Puma:

    # config/puma.rb
    on_worker_boot do
      # Reestablish your database connection, etc...
      Que.mode = :async
    end

### Managing the Jobs Table

After you've connected Que to the database, you can manage the jobs table:

    # Create/update the jobs table to the latest schema version:
    Que.migrate!

If you're using migration files you'll want to migrate to a specific version, to ensure that your migrations work the same way even when you upgrade Que in the future:

    # Update the schema to version #4.
    Que.migrate! :version => 4

    # To reverse the migration, drop the jobs table entirely:
    Que.migrate! :version => 0

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
