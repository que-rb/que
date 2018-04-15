## Using Sequel

If you're using Sequel, with or without Rails, you'll need to give Que a specific database instance to use:

```ruby
DB = Sequel.connect(ENV['DATABASE_URL'])
Que.connection = DB
```

If you are using Sequel's migrator, your app initialization won't happen, so you may need to tweak your migrations to `require 'que'` and set its connection:

```ruby
require 'que'
Sequel.migration do
  up do
    Que.connection = self
    Que.migrate! :version => 3
  end
  down do
    Que.connection = self
    Que.migrate! :version => 0
  end
end
```

Then you can safely use the same database object to transactionally protect your jobs:

```ruby
class MyJob < Que::Job
  def run(user_id:)
    # Do stuff.

    DB.transaction do
      # Make changes to the database.

      # Destroying this job will be protected by the same transaction.
      destroy
    end
  end
end

# Or, in your controller action:
DB.transaction do
  @user = User.create(params[:user])
  MyJob.enqueue user_id: @user.id
end
```

Sequel automatically wraps model persistance actions (create, update, destroy) in transactions, so you can simply call #enqueue methods from your models' callbacks, if you wish.
