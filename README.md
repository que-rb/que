# Que

**TL;DR: Que is a high-performance alternative to DelayedJob or QueueClassic that improves the reliability of your application by helping you keep your jobs [consistent](https://en.wikipedia.org/wiki/ACID#Consistency) with the rest of your data.**

Que is a queue for Ruby and PostgreSQL that manages jobs using [advisory locks](http://www.postgresql.org/docs/current/static/explicit-locking.html#ADVISORY-LOCKS), which gives it several advantages over other RDBMS-backed queues:

* **Concurrency** - Workers don't block each other when trying to lock jobs, as often occurs with "SELECT FOR UPDATE"-style locking. This allows for very high throughput with a large number of workers.
* **Efficiency** - Locks are held in memory, so locking a job doesn't incur a disk write. These first two points are what limit performance with other queues - all workers trying to lock jobs have to wait behind one that's persisting its UPDATE on a locked_at column to disk (and the disks of however many other servers your database is replicating to). Under heavy load, Que's bottleneck is CPU, not I/O.
* **Safety** - If a Ruby process dies, the jobs it is working won't be lost, or left in a locked or ambiguous state - they immediately become available for any other worker to pick up.

Additionally, there are the general benefits of storing jobs in Postgres, alongside the rest of your data, rather than in Redis or a dedicated queue:

* **Transactional Control** - Queue a job along with other changes to your database, and it'll commit or rollback with everything else. If you're using ActiveRecord or Sequel, Que can piggyback on their connections, so setup is simple and jobs are protected by the transactions you're already using.
* **Atomic Backups** - Your jobs and data can be backed up together and restored as a snapshot. If your jobs relate to your data (and they usually do), there's no risk of jobs falling through the cracks during a recovery.
* **Fewer Dependencies** - If you're already using Postgres (and you probably should be), a separate queue is another moving part that can break.

Que's primary goal is reliability. When it's stable, you should be able to leave your application running indefinitely without worrying about jobs being lost due to a lack of transactional support, or left in limbo due to a crashing process. Que does everything it can to ensure that jobs you queue are performed exactly once (though the occasional repetition of a job can be impossible to avoid - see the wiki page on [how to write a reliable job](https://github.com/chanks/que/wiki/Writing-Reliable-Jobs)).

Que's secondary goal is performance. It won't be able to match the speed or throughput of a dedicated queue, or maybe even a Redis-backed queue, but it should be fast enough for most use cases. In [benchmarks](https://github.com/chanks/queue-shootout) on an AWS c3.8xlarge instance, Que approaches 10,000 jobs per second, or about twenty times the throughput of DelayedJob or QueueClassic. You are encouraged to try things out on your own production hardware, though.

Que also includes a worker pool, so that multiple threads can process jobs in the same process. It can even do this in the background of your web process - if you're running on Heroku, for example, you won't need to run a separate worker dyno.

*Please be careful when running Que in production. It's still very new compared to other RDBMS-backed queues, and there may be issues that haven't been ironed out yet. Bug reports are welcome.*

Que is tested on Ruby 2.0, Rubinius and JRuby (with the `jruby-pg` gem, which is [not yet functional with ActiveRecord](https://github.com/chanks/que/issues/4#issuecomment-29561356)). It requires Postgres 9.2+ for the JSON datatype.

## Installation

Add this line to your application's Gemfile:

    gem 'que'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install que

## Usage

The following is assuming you're using Rails 4.0. Que hasn't been tested with previous versions of Rails.

First, generate a migration for the job table.

    rails generate que:install
    rake db:migrate

Create a class for each type of job you want to run:

    # app/jobs/charge_credit_card.rb
    class ChargeCreditCard < Que::Job
      # Custom job options.
      @default_priority = 3
      @default_run_at = proc { 1.minute.from_now }

      def run(user_id, card_id, your_options = {})
        # Do stuff.

        ActiveRecord::Base.transaction do
          # Write any changes you'd like to the database.

          # It's best to destroy the job in the same transaction as any other
          # changes you make. Que will destroy the job for you after the run
          # method if you don't do it yourself, but if your job writes to the
          # DB but doesn't destroy the job in the same transaction, it's
          # possible that the job could be repeated in the event of a crash.
          destroy
        end
      end
    end

Queue your job. Again, it's best to do this in a transaction with other changes you're making. Also note that any arguments you pass will be serialized to JSON and back again, so stick to simple types (strings, integers, floats, hashes, and arrays).

    ActiveRecord::Base.transaction do
      # Persist credit card information
      card = CreditCard.create(params[:credit_card])
      ChargeCreditCard.queue(current_user.id, card.id, :your_custom_option => 'whatever')
    end

You can also schedule it to run at a specific time, or with a specific priority:

    # 1 is high priority, 5 is low priority.
    ChargeCreditCard.queue current_user.id, card.id, :your_custom_option => 'whatever', :run_at => 1.day.from_now, :priority => 5

To determine what happens when a job is queued, you can set Que's mode with `Que.mode = :off` or `config.que.mode = :off` in your application configuration. There are a few options for the mode:

* `:off` - In this mode, queueing a job will simply insert it into the database - the current process will make no effort to run it. You should use this if you want to use a dedicated process to work tasks (there's a rake task to do this, see below). This is the default when running `rails console` in the development or production environments.
* `:async` - In this mode, a pool of background workers is spun up, each running in their own thread. They will intermittently check for new jobs. This is the default when running `rails server` in the development or production environments. By default, there are 4 workers and they'll check for a new job every 5 seconds. You can modify these options with `Que.worker_count = 8` or `config.que.worker_count = 8` and `Que.sleep_period = 1` or `config.que.sleep_period = 1`.
* `:sync` - In this mode, any jobs you queue will be run in the same thread, synchronously (that is, `MyJob.queue` runs the job and won't return until it's completed). This makes your application's behavior easier to test, so it's the default in the test environment.

If you don't want to run workers in your web process, you can also work jobs in a rake task, similar to how other queueing systems work:

    # Run a pool of 4 workers.
    rake que:work

    # Or configure the number of workers.
    WORKER_COUNT=8 rake que:work

    # If your app code isn't thread-safe, be sure to stick to one worker.
    WORKER_COUNT=1 rake que:work

If an error causes a job to fail, Que will repeat that job at exponentially-increasing intervals, similar to DelayedJob (the job will be retried at 4 seconds, 19 seconds, 84 seconds, 259 seconds...). You can also hook Que into whatever error notification system you're using:

    config.que.error_handler = proc do |error|
      # Do whatever you want with the error object.
    end

You can find more documentation on the [Github wiki](https://github.com/chanks/que/wiki).

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

A note on running specs - Que's worker system is multithreaded and therefore prone to race conditions (especially on Rubinius). As such, if you've touched that code, a single spec run passing isn't a guarantee that any changes you've made haven't introduced bugs. One thing I like to do before pushing changes is rerun the specs many times and watching for hangs. You can do this from the command line with something like:

    for i in {1..1000}; do rspec -b --seed $i; done

This will iterate the specs one thousand times, each with a different ordering. If the specs hang, note what the seed number was on that iteration. For example, if the previous specs finished with a "Randomized with seed 328", you know that there's a hang with seed 329, and you can narrow it down to a specific spec with:

    for i in {1..1000}; do LOG_SPEC=true rspec -b --seed 329; done

Note that we iterate because there's no guarantee that the hang would reappear with a single additional run, so we need to rerun the specs until it reappears. The LOG_SPEC parameter will output the name and file location of each spec before it is run, so you can easily tell which spec is hanging, and you can continue narrowing things down from there.
