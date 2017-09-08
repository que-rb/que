## Using Plain Postgres Connections

If you're not using an ORM like ActiveRecord or Sequel, you can use a distinct connection pool to manage your Postgres connections. Please be aware that if you **are** using ActiveRecord or Sequel, there's no reason for you to be using any of these methods - it's less efficient (unnecessary connections will waste memory on your database server) and you lose the reliability benefits of wrapping jobs in the same transactions as the rest of your data.

## Using ConnectionPool or Pond

Support for two connection pool gems is included in Que. The first is the ConnectionPool gem (be sure to add `gem 'connection_pool'` to your Gemfile):

```ruby
require 'uri'
require 'pg'
require 'connection_pool'

uri = URI.parse(ENV['DATABASE_URL'])

Que.connection = ConnectionPool.new(size: 10) do
  PG::Connection.open(
    host:     uri.host,
    user:     uri.user,
    password: uri.password,
    port:     uri.port || 5432,
    dbname:   uri.path[1..-1]
  )end
```

Be sure to pick your pool size carefully - if you use 10 for the size, you'll incur the overhead of having 10 connections open to Postgres even if you never use more than a couple of them.

The Pond gem doesn't have this drawback - it is very similar to ConnectionPool, but establishes connections lazily (add `gem 'pond'` to your Gemfile):

```ruby
require 'uri'
require 'pg'
require 'pond'

uri = URI.parse(ENV['DATABASE_URL'])

Que.connection = Pond.new(maximum_size: 10) do
  PG::Connection.open(
    host:     uri.host,
    user:     uri.user,
    password: uri.password,
    port:     uri.port || 5432,
    dbname:   uri.path[1..-1]
  )
end
```

## Using Any Other Connection Pool

You can use any other in-process connection pool by defining access to it in a proc that's passed to `Que.connection_proc = proc`. The proc you pass should accept a block and call it with a connection object. For instance, Que's built-in interface to Sequel's connection pool is basically implemented like:

```ruby
Que.connection_proc = proc do |&block|
  DB.synchronize do |connection|
    block.call(connection)
  end
end
```

This proc must meet a few requirements:
- The yielded object must be an instance of `PG::Connection`.
- It must be reentrant - if it is called with a block, and then called again inside that block, it must return the same object. For example, in `proc.call{|conn1| proc.call{|conn2| conn1.object_id == conn2.object_id}}` the innermost condition must be true.
- It must lock the connection object and prevent any other thread from accessing it for the duration of the block.

If any of these conditions aren't met, Que will raise an error.
