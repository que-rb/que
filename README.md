# Que ![tests](https://github.com/que-rb/que/workflows/tests/badge.svg)

**This README and the rest of the docs on the master branch all refer to Que 2.x. For older versions, please refer to the docs on the respective branches: [1.x](https://github.com/que-rb/que/tree/1.x), or [0.x](https://github.com/que-rb/que/tree/0.x).**

*TL;DR: Que is a high-performance job queue that improves the reliability of your application by protecting your jobs with the same [ACID guarantees](https://en.wikipedia.org/wiki/ACID) as the rest of your data.*

Que ("keɪ", or "kay") is a queue for Ruby and PostgreSQL that manages jobs using [advisory locks](http://www.postgresql.org/docs/current/static/explicit-locking.html#ADVISORY-LOCKS), which gives it several advantages over other RDBMS-backed queues:

- **Concurrency** - Workers don't block each other when trying to lock jobs, as often occurs with "SELECT FOR UPDATE"-style locking. This allows for very high throughput with a large number of workers.
- **Efficiency** - Locks are held in memory, so locking a job doesn't incur a disk write. These first two points are what limit performance with other queues. Under heavy load, Que's bottleneck is CPU, not I/O.
- **Safety** - If a Ruby process dies, the jobs it's working won't be lost, or left in a locked or ambiguous state - they immediately become available for any other worker to pick up.

Additionally, there are the general benefits of storing jobs in Postgres, alongside the rest of your data, rather than in Redis or a dedicated queue:

- **Transactional Control** - Queue a job along with other changes to your database, and it'll commit or rollback with everything else. If you're using ActiveRecord or Sequel, Que can piggyback on their connections, so setup is simple and jobs are protected by the transactions you're already using.
- **Atomic Backups** - Your jobs and data can be backed up together and restored as a snapshot. If your jobs relate to your data (and they usually do), there's no risk of jobs falling through the cracks during a recovery.
- **Fewer Dependencies** - If you're already using Postgres (and you probably should be), a separate queue is another moving part that can break.
- **Security** - Postgres' support for SSL connections keeps your data safe in transport, for added protection when you're running workers on cloud platforms that you can't completely control.

Que's primary goal is reliability. You should be able to leave your application running indefinitely without worrying about jobs being lost due to a lack of transactional support, or left in limbo due to a crashing process. Que does everything it can to ensure that jobs you queue are performed exactly once (though the occasional repetition of a job can be impossible to avoid - see the docs on [how to write a reliable job](/docs/README.md#writing-reliable-jobs)).

Que's secondary goal is performance. The worker process is multithreaded, so that a single process can run many jobs simultaneously.

Compatibility:

- MRI Ruby 2.7+ (for Ruby 3, Que 2+ is required)
- PostgreSQL 9.5+
- Rails 6.0+ (optional)

**Please note** - Que's job table undergoes a lot of churn when it is under high load, and like any heavily-written table, is susceptible to bloat and slowness if Postgres isn't able to clean it up. The most common cause of this is long-running transactions, so it's recommended to try to keep all transactions against the database housing Que's job table as short as possible. This is good advice to remember for any high-activity database, but bears emphasizing when using tables that undergo a lot of writes.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'que'
```

And then execute:

```bash
bundle
```

Or install it yourself as:

```bash
gem install que
```

## Usage

First, create the queue schema in a migration. For example:

```ruby
class CreateQueSchema < ActiveRecord::Migration[6.0]
  def up
    # Whenever you use Que in a migration, always specify the version you're
    # migrating to. If you're unsure what the current version is, check the
    # changelog.
    Que.migrate!(version: 7)
  end

  def down
    # Migrate to version 0 to remove Que entirely.
    Que.migrate!(version: 0)
  end
end
```

Create a class for each type of job you want to run:

```ruby
# app/jobs/charge_credit_card.rb
class ChargeCreditCard < Que::Job
  # Default settings for this job. These are optional - without them, jobs
  # will default to priority 100 and run immediately.
  self.run_at = proc { 1.minute.from_now }

  # We use the Linux priority scale - a lower number is more important.
  self.priority = 10

  def run(credit_card_id, user_id:)
    # Do stuff.
    user = User.find(user_id)
    card = CreditCard.find(credit_card_id)

    User.transaction do
      # Write any changes you'd like to the database.
      user.update charged_at: Time.now

      # It's best to destroy the job in the same transaction as any other
      # changes you make. Que will mark the job as destroyed for you after the
      # run method if you don't do it yourself; however if your job writes to the DB
      # but doesn't destroy the job in the same transaction, it's possible that
      # the job could be repeated in the event of a crash.
      destroy

      # If you'd rather leave the job record in the database to maintain a job
      # history, simply replace the `destroy` call with a `finish` call.
    end
  end
end
```

Queue your job. Again, it's best to do this in a transaction with other changes you're making. Also note that any arguments you pass will be serialized to JSON and back again, so stick to simple types (strings, integers, floats, hashes, and arrays).

```ruby
CreditCard.transaction do
  # Persist credit card information
  card = CreditCard.create(params[:credit_card])
  ChargeCreditCard.enqueue(card.id, user_id: current_user.id)
end
```

You can also add options to run the job after a specific time, or with a specific priority:

```ruby
ChargeCreditCard.enqueue(card.id, user_id: current_user.id, job_options: { run_at: 1.day.from_now, priority: 5 })
```

[Learn more about job options](docs/README.md#job-options).

## Running the Que Worker

In order to process jobs, you must start a separate worker process outside of your main server.

```bash
bundle exec que
```

Try running `que -h` to get a list of runtime options:

```
$ que -h
usage: que [options] [file/to/require] ...
    -h, --help                       Show this help text.
    -i, --poll-interval [INTERVAL]   Set maximum interval between polls for available jobs, in seconds (default: 5)
    ...
```

You may need to pass que a file path to require so that it can load your app. Que will automatically load `config/environment.rb` if it exists, so you shouldn't need an argument if you're using Rails.

## Additional Rails-specific Setup

If you're using ActiveRecord to dump your database's schema, please [set your schema_format to :sql](http://guides.rubyonrails.org/migrations.html#types-of-schema-dumps) so that Que's table structure is managed correctly. This is a good idea regardless, as the `:ruby` schema format doesn't support many of PostgreSQL's advanced features.

Pre-1.0, the default queue name needed to be configured in order for Que to work out of the box with Rails. As of 1.0 the default queue name is now 'default', as Rails expects, but when Rails enqueues some types of jobs it may try to use another queue name that isn't worked by default. You can either:

- [Configure Rails](https://guides.rubyonrails.org/configuring.html) to send all internal job types to the 'default' queue by adding the following to `config/application.rb`:

    ```ruby
    config.action_mailer.deliver_later_queue_name = :default
    config.action_mailbox.queues.incineration = :default
    config.action_mailbox.queues.routing = :default
    config.active_storage.queues.analysis = :default
    config.active_storage.queues.purge = :default
    ```

- [Tell que](/docs#multiple-queues) to work all of these queues (less efficient because it requires polling all of them):

    ```bash
    que -q default -q mailers -q action_mailbox_incineration -q action_mailbox_routing -q active_storage_analysis -q active_storage_purge
    ```

Also, if you would like to integrate Que with Active Job, you can do it by setting the adapter in `config/application.rb` or in a specific environment by setting it in `config/environments/production.rb`, for example:

```ruby
config.active_job.queue_adapter = :que
```

Que will automatically use the database configuration of your rails application, so there is no need to configure anything else.

You can then write your jobs as usual following the [Active Job documentation](https://guides.rubyonrails.org/active_job_basics.html). However, be aware that you'll lose the ability to finish the job in the same transaction as other database operations. That happens because Active Job is a generic background job framework that doesn't benefit from the database integration Que provides.

If you later decide to switch a job from Active Job to Que to have transactional integrity you can easily change the corresponding job class to inherit from `Que::Job` and follow the usage guidelines in the previous section.

## Testing

There are a couple ways to do testing. You may want to set `Que::Job.run_synchronously = true`, which will cause JobClass.enqueue to simply execute the job's logic synchronously, as if you'd run JobClass.run(*your_args). Or, you may want to leave it disabled so you can assert on the job state once they are stored in the database.

## Documentation

**For full documentation, see [here](docs/README.md)**.

## Related Projects

These projects are tested to be compatible with Que 1.x:

- [que-web](https://github.com/statianzo/que-web) is a Sinatra-based UI for inspecting your job queue.
- [que-view](https://github.com/kortirso/que-view) is a Rails engine-based UI for inspecting your job queue.
- [que-scheduler](https://github.com/hlascelles/que-scheduler) lets you schedule tasks using a cron style config file.
- [que-locks](https://github.com/airhorns/que-locks) lets you lock around job execution for so only one job runs at once for a set of arguments.
- [que-unique](https://github.com/bambooengineering/que-unique) provides fast in-memory `enqueue` deduping.
- [que-prometheus](https://github.com/mnbbrown/que-prometheus) exposes Prometheus API endpoints for job, worker, and queue metrics

If you have a project that uses or relates to Que, feel free to submit a PR adding it to the list!

## Community and Contributing

- For feature suggestions or bugs in the library, please feel free to [open an issue](https://github.com/que-rb/que/issues/new).
- For general discussion and questions/concerns that don't relate to obvious bugs, join our [Discord Server](https://discord.gg/B3EW32H).
- For contributions, pull requests submitted via Github are welcome.

Regarding contributions, one of the project's priorities is to keep Que as simple, lightweight and dependency-free as possible, and pull requests that change too much or wouldn't be useful to the majority of Que's users have a good chance of being rejected. If you're thinking of submitting a pull request that adds a new feature, consider starting a discussion in an issue first about what it would do and how it would be implemented. If it's a sufficiently large feature, or if most of Que's users wouldn't find it useful, it may be best implemented as a standalone gem, like some of the related projects above.

### Specs

A note on running specs - Que's worker system is multithreaded and therefore prone to race conditions. As such, if you've touched that code, a single spec run passing isn't a guarantee that any changes you've made haven't introduced bugs. One thing I like to do before pushing changes is rerun the specs many times and watching for hangs. You can do this from the command line with something like:

```bash
for i in {1..1000}; do SEED=$i bundle exec rake; done
```

This will iterate the specs one thousand times, each with a different ordering. If the specs hang, note what the seed number was on that iteration. For example, if the previous specs finished with a "Randomized with seed 328", you know that there's a hang with seed 329, and you can narrow it down to a specific spec with:

```bash
for i in {1..1000}; do LOG_SPEC=true SEED=328 bundle exec rake; done
```

Note that we iterate because there's no guarantee that the hang would reappear with a single additional run, so we need to rerun the specs until it reappears. The LOG_SPEC parameter will output the name and file location of each spec before it is run, so you can easily tell which spec is hanging, and you can continue narrowing things down from there.

Another helpful technique is to replace an `it` spec declaration with `hit` - this will run that particular spec 100 times during the run.

#### With Docker

We've provided a Dockerised environment to avoid the need to manually: install Ruby, install the gem bundle, set up Postgres, and connect to the database.

To run the specs using this environment, run:

```bash
./auto/test
```

To get a shell in the environment, run:

```bash
./auto/dev
```

The [Docker Compose config](docker-compose.yml) provides a convenient way to inject your local shell aliases into the Docker container. Simply create a file containing your alias definitions (or which sources them from other files) at `~/.docker-rc.d/.docker-bashrc`, and they will be available inside the container.

#### Without Docker

You'll need to have Postgres running. Assuming you have it running on port 5697, with a `que-test` database, and a username & password of `que`, you can run:

```bash
DATABASE_URL=postgres://que:que@localhost:5697/que-test bundle exec rake
```

If you don't already have Postgres, you could use Docker Compose to run just the database:

```bash
docker compose up -d db
```

If you want to try a different version of Postgres, e.g. 12:

```bash
export POSTGRES_VERSION=12
```

### Git pre-push hook

So we can avoid breaking the build, we've created Git pre-push hooks to verify everything is ok before pushing.

To set up the pre-push hook locally, run:

```bash
echo -e "#\!/bin/bash\n\$(dirname \$0)/../../auto/pre-push-hook" > .git/hooks/pre-push
chmod +x .git/hooks/pre-push
```

### Release process

The process for releasing a new version of the gem is:

- Merge PR(s)
- Git pull locally
- Update the version number, bundle install, and commit
- Update `CHANGELOG.md`, and commit
- Tag the commit with the version number, prefixed by `v`
- Git push to master
- Git push the tag
- Publish the new version of the gem to RubyGems: `gem build -o que.gem && gem push que.gem`
- Create a GitHub release - rather than describe anything there, link to the heading for the release in `CHANGELOG.md`
- Post on the Que Discord in `#announcements`
