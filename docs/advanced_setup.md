### Alternate Connection Types

The project README covers the common case of using Que with Rails and ActiveRecord. If you're using ActiveRecord but not Rails, there won't be a Railtie to set things up for you, so you'll need to tell Que to use ActiveRecord's connection pool:

    Que.connection = ActiveRecord

If you're using Sequel, with or without Rails, you'll need to give Que a specific database instance to use:

    DB = Sequel.connect(ENV['DATABASE_URL'])
    Que.connection = DB

Then you can safely use transactions in your jobs:

    class MyJob < Que::Job
      def run
        DB.transaction do
          # Make whatever changes you like to the database.
          destroy
        end
      end
    end

If you're not using an ORM, you can have Que use a plain Postgres connection:

    require 'uri'
    require 'pg'

    uri = URI.parse(ENV['DATABASE_URL'])
    Que.connection = PG::Connection.open :host     => uri.host,
                                         :user     => uri.user,
                                         :password => uri.password,
                                         :port     => uri.port || 5432,
                                         :dbname   => uri.path[1..-1]

If you want to be able to use multithreading to run multiple jobs simultaneously, though, it'll be much more efficient (though not absolutely necessary) to use the ConnectionPool gem (be sure to add `gem 'connection_pool'` to your Gemfile):

    require 'uri'
    require 'pg'
    require 'connection_pool'

    uri  = URI.parse(ENV['DATABASE_URL'])
    pool = ConnectionPool.new :size => 10 do
      PG::Connection.open :host     => uri.host,
                          :user     => uri.user,
                          :password => uri.password,
                          :port     => uri.port || 5432,
                          :dbname   => uri.path[1..-1]
    end

### Other Options

Set up a logger to use:

    Que.logger = Logger.new(STDOUT)

Start up the worker pool:

    Que.mode = :async
    Que.worker_count = 8

The default number of workers is 4, but the ideal number for your app will depend on your interpreter and what types of jobs you're running. JRuby and Rubinius have no global interpreter lock, and so can make use of multiple CPU cores, so you could potentially set the number of workers very high for them. Otherwise, all your threads will be sharing a single CPU, and unless your jobs spend a lot of time waiting on I/O, setting the worker_count very high will become counterproductive. You should experiment to find the best setting for your use case.

When the worker pool is running, one worker will be prompted to look for new jobs once every five seconds. If you want to change this period, you can do:

    Que.sleep_period = 1
