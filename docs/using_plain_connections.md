## Using Plain Postgres Connections

If you're not using an ORM like ActiveRecord or Sequel, you can have Que access jobs using a plain Postgres connection:

    require 'uri'
    require 'pg'

    uri = URI.parse(ENV['DATABASE_URL'])

    Que.connection = PG::Connection.open :host     => uri.host,
                                         :user     => uri.user,
                                         :password => uri.password,
                                         :port     => uri.port || 5432,
                                         :dbname   => uri.path[1..-1]

If you want to be able to use multithreading to run multiple jobs simultaneously in the same process, though, you'll need the ConnectionPool gem (be sure to add `gem 'connection_pool'` to your Gemfile):

    require 'uri'
    require 'pg'
    require 'connection_pool'

    uri = URI.parse(ENV['DATABASE_URL'])

    Que.connection = ConnectionPool.new :size => 10 do
      PG::Connection.open :host     => uri.host,
                          :user     => uri.user,
                          :password => uri.password,
                          :port     => uri.port || 5432,
                          :dbname   => uri.path[1..-1]
    end

Be sure to pick your pool size carefully - if you use 10 for the size, you'll incur the overhead of having 10 connections open to Postgres even if you never use more than a couple of them.

Please be aware that if you're using ActiveRecord or Sequel to manage your data, there's no reason for you to be using either of these methods - it's less efficient (unnecessary connections will waste memory on your database server) and you lose the reliability benefits of wrapping jobs in the same transactions as the rest of your data.
