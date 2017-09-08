## Using Sequel

If you're using Sequel, with or without Rails, you'll need to give Que a specific database instance to use:

```ruby
DB = Sequel.connect(ENV['DATABASE_URL'])
Que.connection = DB
```

Then you can safely use the same database object to transactionally protect your jobs:

```ruby
class MyJob < Que::Job
  def run(user_id:)
    # Do stuff.

    DB.transaction do
      # Make changes to the database.

      # Finishing this job will be protected by the same transaction.
      finish
    end
  end
end

# In your controller action:
DB.transaction do
  @user = User.create(params[:user])
  MyJob.enqueue user_id: @user.id
end
```
