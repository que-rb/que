## Using Plain Postgres Connections

If you're not using an ORM like ActiveRecord or Sequel, you can use one of two gems to manage a connection pool for your PG connections. The first is the ConnectionPool gem (be sure to add `gem 'connection_pool'` to your Gemfile):

```ruby
require 'uri'
require 'pg'
require 'connection_pool'

uri = URI.parse(ENV['DATABASE_URL'])

Que.connection = ConnectionPool.new :size => 10 do
  PG::Connection.open host:     uri.host,
                      user:     uri.user,
                      password: uri.password,
                      port:     uri.port || 5432,
                      dbname:   uri.path[1..-1]
end
```

Be sure to pick your pool size carefully - if you use 10 for the size, you'll incur the overhead of having 10 connections open to Postgres even if you never use more than a couple of them.

The Pond gem doesn't have this drawback - it is very similar to ConnectionPool, but establishes connections lazily (add `gem 'pond'` to your Gemfile):

```ruby
require 'uri'
require 'pg'
require 'pond'

uri = URI.parse(ENV['DATABASE_URL'])

Que.connection = Pond.new :maximum_size => 10 do
  PG::Connection.open host:     uri.host,
                      user:     uri.user,
                      password: uri.password,
                      port:     uri.port || 5432,
                      dbname:   uri.path[1..-1]
end
```

Please be aware that if you're using ActiveRecord or Sequel to manage your data, there's no reason for you to be using any of these methods - it's less efficient (unnecessary connections will waste memory on your database server) and you lose the reliability benefits of wrapping jobs in the same transactions as the rest of your data. In general, your app should probably be using a connection pool, and Que should probably hook into whatever connection pool you're already using.
