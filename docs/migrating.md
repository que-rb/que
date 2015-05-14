## Migrating

Some new releases of Que may require updates to the database schema. It's recommended that you integrate these updates alongside your other database migrations. For example, when Que released version 0.6.0, the schema version was updated from 2 to 3. If you're running ActiveRecord, you could make a migration to perform this upgrade like so:

```ruby
class UpdateQue < ActiveRecord::Migration
  def self.up
    Que.migrate! version: 3
  end

  def self.down
    Que.migrate! version: 2
  end
end
```

This will make sure that your database schema stays consistent with your codebase. If you're looking for something quicker and dirtier, you can always manually migrate in a console session:

```ruby
# Change schema to version 3.
Que.migrate! version: 3

# Update to whatever the latest schema version is.
Que.migrate!

# Check your current schema version.
Que.db_version #=> 3
```

Note that you can remove Que from your database completely by migrating to version 0.
