## Advanced Setup

If you're using both Rails and ActiveRecord, the README describes how to get started (which is pretty straightforward, since Que includes a Railtie that handles a lot of setup for you). Otherwise, you'll need to do some manual setup.

### Setting the Connection Proc

The biggest part of Que's setup involves hooking it into whatever connection pool you're already using so that your jobs can be transactionally protected.

You'll need to set Que.connection_proc to a callable object that yields a PG::Connection object. This is not as hard as it might sound - see the following examples:

##### ActiveRecord (Outside of Rails)

ActiveRecord hides the PG::Connection object behind an extra layer of abstraction, so things are a little messy, but still pretty straightforward:

    Que.connection_proc = proc do |&block|
      ActiveRecord::Base.connection_pool.with_connection { |conn| block.call(conn.raw_connection) }
    end

This is exactly what the Railtie that ships with Que does behind the scenes. With this setup you can safely use transaction blocks just as you would if you were using Rails:

    ActiveRecord::Base.transaction do
      @user = User.create(params[:user])
      SendRegistrationEmail.enqueue :user_id => @user.id
    end

##### Sequel

If you're using Sequel, setup is even simpler. Que can use the `synchronize` method of the database you've already set up:

    DB = Sequel.connect(ENV['DATABASE_URL'])
    Que.connection_proc = DB.method(:synchronize)

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

    Que.connection_proc = pool.method(:with)

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

    Que.connection_proc = pond.method(:checkout)

##### Other Connection Pools

If you're using an ORM or other database library not covered here, Que can probably work with it without too much issue. You can set connection_proc to a Proc containing any logic you like, so long as its call method is thread-safe, yields a PG::Connection object, and is [reentrant](https://en.wikipedia.org/wiki/Reentrancy_(computing)). Reentrancy means that, for the proc you give Que, the following must print true:

    connection_proc = Proc.new do |&block|
      # Your logic here, which safely locks a PG::Connection and passes it to block.call()
    end

    connection_proc.call do |o1|
      connection_proc.call do |o2|
        puts o1 == o2 # Should be true.
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
