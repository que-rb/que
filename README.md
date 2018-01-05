# Que

**TL;DR: Que is a high-performance alternative to DelayedJob or QueueClassic that improves the reliability of your application by protecting your jobs with the same [ACID guarantees](https://en.wikipedia.org/wiki/ACID) as the rest of your data.**

Que ("keɪ", or "kay") is a queue for Ruby and PostgreSQL that manages jobs using [advisory locks](http://www.postgresql.org/docs/current/static/explicit-locking.html#ADVISORY-LOCKS), which gives it several advantages over other RDBMS-backed queues:

  * **Concurrency** - Workers don't block each other when trying to lock jobs, as often occurs with "SELECT FOR UPDATE"-style locking. This allows for very high throughput with a large number of workers.
  * **Efficiency** - Locks are held in memory, so locking a job doesn't incur a disk write. These first two points are what limit performance with other queues - all workers trying to lock jobs have to wait behind one that's persisting its UPDATE on a locked_at column to disk (and the disks of however many other servers your database is synchronously replicating to). Under heavy load, Que's bottleneck is CPU, not I/O.
  * **Safety** - If a Ruby process dies, the jobs it's working won't be lost, or left in a locked or ambiguous state - they immediately become available for any other worker to pick up.

Additionally, there are the general benefits of storing jobs in Postgres, alongside the rest of your data, rather than in Redis or a dedicated queue:

  * **Transactional Control** - Queue a job along with other changes to your database, and it'll commit or rollback with everything else. If you're using ActiveRecord or Sequel, Que can piggyback on their connections, so setup is simple and jobs are protected by the transactions you're already using.
  * **Atomic Backups** - Your jobs and data can be backed up together and restored as a snapshot. If your jobs relate to your data (and they usually do), there's no risk of jobs falling through the cracks during a recovery.
  * **Fewer Dependencies** - If you're already using Postgres (and you probably should be), a separate queue is another moving part that can break.
  * **Security** - Postgres' support for SSL connections keeps your data safe in transport, for added protection when you're running workers on cloud platforms that you can't completely control.

Que's primary goal is reliability. You should be able to leave your application running indefinitely without worrying about jobs being lost due to a lack of transactional support, or left in limbo due to a crashing process. Que does everything it can to ensure that jobs you queue are performed exactly once (though the occasional repetition of a job can be impossible to avoid - see the docs on [how to write a reliable job](https://github.com/chanks/que/blob/master/docs/writing_reliable_jobs.md)).

Que's secondary goal is performance. It won't be able to match the speed or throughput of a dedicated queue, or maybe even a Redis-backed queue, but it should be fast enough for most use cases. In [benchmarks of RDBMS queues](https://github.com/chanks/queue-shootout) using PostgreSQL 9.3 on a AWS c3.8xlarge instance, Que approaches 10,000 jobs per second, or about twenty times the throughput of DelayedJob or QueueClassic. You are encouraged to try things out on your own production hardware, though.

Que also includes a worker pool, so that multiple threads can process jobs in the same process. It can even do this in the background of your web process - if you're running on Heroku, for example, you don't need to run a separate worker dyno.

Que is tested on Ruby 2.0, Rubinius and JRuby (with the `jruby-pg` gem, which is [not yet functional with ActiveRecord](https://github.com/chanks/que/issues/4#issuecomment-29561356)). It requires Postgres 9.2+ for the JSON datatype.

**Please note** - Que's job table undergoes a lot of churn when it is under high load, and like any heavily-written table, is susceptible to bloat and slowness if Postgres isn't able to clean it up. The most common cause of this is long-running transactions, so it's recommended to try to keep all transactions against the database housing Que's job table as short as possible. This is good advice to remember for any high-activity database, but bears emphasizing when using tables that undergo a lot of writes.


## Installation

Add this line to your application's Gemfile:

    gem 'que'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install que


## Usage

The following assumes you're using Rails 4.0 and ActiveRecord. *Que hasn't been tested with versions of Rails before 4.0, and may or may not work with them.* See the [/docs directory](https://github.com/chanks/que/blob/master/docs) for instructions on using Que [outside of Rails](https://github.com/chanks/que/blob/master/docs/advanced_setup.md), and with [Sequel](https://github.com/chanks/que/blob/master/docs/using_sequel.md) or [no ORM](https://github.com/chanks/que/blob/master/docs/using_plain_connections.md), among other things.

First, generate and run a migration for the job table.

    $ bin/rails generate que:install
    $ bin/rake db:migrate

Create a class for each type of job you want to run:


``` ruby
# app/jobs/charge_credit_card.rb
class ChargeCreditCard < Que::Job
  # Default settings for this job. These are optional - without them, jobs
  # will default to priority 100 and run immediately.
  @priority = 10
  @run_at = proc { 1.minute.from_now }

  def run(user_id, options)
    # Do stuff.
    user = User[user_id]
    card = CreditCard[options[:credit_card_id]]

    ActiveRecord::Base.transaction do
      # Write any changes you'd like to the database.
      user.update_attributes :charged_at => Time.now

      # It's best to destroy the job in the same transaction as any other
      # changes you make. Que will destroy the job for you after the run
      # method if you don't do it yourself, but if your job writes to the
      # DB but doesn't destroy the job in the same transaction, it's
      # possible that the job could be repeated in the event of a crash.
      destroy
    end
  end
end
```

Queue your job. Again, it's best to do this in a transaction with other changes you're making. Also note that any arguments you pass will be serialized to JSON and back again, so stick to simple types (strings, integers, floats, hashes, and arrays).

``` ruby
ActiveRecord::Base.transaction do
  # Persist credit card information
  card = CreditCard.create(params[:credit_card])
  ChargeCreditCard.enqueue(current_user.id, :credit_card_id => card.id)
end
```

You can also add options to run the job after a specific time, or with a specific priority:

``` ruby
# The default priority is 100, and a lower number means a higher priority. 5 would be very important.
ChargeCreditCard.enqueue current_user.id, :credit_card_id => card.id, :run_at => 1.day.from_now, :priority => 5
```

To determine what happens when a job is queued, you can set Que's mode. There are a few options for the mode:

  * `Que.mode = :off` - In this mode, queueing a job will simply insert it into the database - the current process will make no effort to run it. You should use this if you want to use a dedicated process to work tasks (there's an executable included that will do this, `que`). This is the default when running `bin/rails console`.
  * `Que.mode = :async` - In this mode, a pool of background workers is spun up, each running in their own thread. See the docs for [more information on managing workers](https://github.com/chanks/que/blob/master/docs/managing_workers.md).
  * `Que.mode = :sync` - In this mode, any jobs you queue will be run in the same thread, synchronously (that is, `MyJob.enqueue` runs the job and won't return until it's completed). This makes your application's behavior easier to test, so it's the default in the test environment.

**If you're using ActiveRecord to dump your database's schema, [set your schema_format to :sql](http://guides.rubyonrails.org/migrations.html#types-of-schema-dumps) so that Que's table structure is managed correctly.** (You can use schema_format as :ruby if you want but keep in mind this is highly advised against, as some parts of Que will not work.)


## Related Projects

  * [que-web](https://github.com/statianzo/que-web) is a Sinatra-based UI for inspecting your job queue.
  * [que-testing](https://github.com/statianzo/que-testing) allows making assertions on enqueued jobs.
  * [que-scheduler](https://github.com/hlascelles/que-scheduler) is a cron scheduler for Que jobs that runs on Que itself.
  * [que-go](https://github.com/bgentry/que-go) is a port of Que for the Go programming language. It uses the same table structure, so that you can use the same job queue from Ruby and Go applications.
  * [wisper-que](https://github.com/joevandyk/wisper-que) adds support for Que to [wisper](https://github.com/krisleech/wisper).

If you have a project that uses or relates to Que, feel free to submit a PR adding it to the list!


## Community and Contributing

  * For bugs in the library, please feel free to [open an issue](https://github.com/chanks/que/issues/new).
  * For general discussion and questions/concerns that don't relate to obvious bugs, try posting on the [que-talk Google Group](https://groups.google.com/forum/#!forum/que-talk).
  * For contributions, pull requests submitted via Github are welcome.

Regarding contributions, one of the project's priorities is to keep Que as simple, lightweight and dependency-free as possible, and pull requests that change too much or wouldn't be useful to the majority of Que's users have a good chance of being rejected. If you're thinking of submitting a pull request that adds a new feature, consider starting a discussion in [que-talk](https://groups.google.com/forum/#!forum/que-talk) first about what it would do and how it would be implemented. If it's a sufficiently large feature, or if most of Que's users wouldn't find it useful, it may be best implemented as a standalone gem, like some of the related projects above.


### Specs

A note on running specs - Que's worker system is multithreaded and therefore prone to race conditions (especially on interpreters without a global lock, like Rubinius or JRuby). As such, if you've touched that code, a single spec run passing isn't a guarantee that any changes you've made haven't introduced bugs. One thing I like to do before pushing changes is rerun the specs many times and watching for hangs. You can do this from the command line with something like:

    for i in {1..1000}; do bundle exec rspec -b --seed $i; done

This will iterate the specs one thousand times, each with a different ordering. If the specs hang, note what the seed number was on that iteration. For example, if the previous specs finished with a "Randomized with seed 328", you know that there's a hang with seed 329, and you can narrow it down to a specific spec with:

    for i in {1..1000}; do LOG_SPEC=true bundle exec rspec -b --seed 329; done

Note that we iterate because there's no guarantee that the hang would reappear with a single additional run, so we need to rerun the specs until it reappears. The LOG_SPEC parameter will output the name and file location of each spec before it is run, so you can easily tell which spec is hanging, and you can continue narrowing things down from there.
