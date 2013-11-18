# Que

Que is a queue for Ruby applications that manages jobs using PostgreSQL's advisory locks. There are several advantages to this design:

* **Safety** - If a worker dies, its jobs won't be lost, or left in a locked or ambiguous state - they immediately become available for any other worker to pick up.
* **Efficiency** - Locking a job doesn't incur a disk write or hold open a transaction.
* **Concurrency** - Since there's no locked_at column or SELECT FOR UPDATE-style locking, workers don't block each other when locking jobs. There's no need to loop through the locking query and catch errors, or resort to hacks to try to prevent multiple workers from trying to lock the same job.

Additionally, there are the general benefits of storing jobs in Postgres rather than a dedicated queue:

* **Transactional control** - Queue a job along with other changes to your database, and they'll commit or rollback with everything else.
* **Fewer dependencies** - If you're already using Postgres (and you probably should be), a separate queue is another moving part that can break.
* **Atomic backups** - Your jobs and data can be backed up together and restored as a snapshot. If your jobs relate to your data (and they usually do), this is important if you don't want to lose anything during a restoration.

Que's primary goal is reliability. You should be able to leave your application running indefinitely without having to manually intervene when jobs are lost due to a lack of transactional support, left in limbo due to a crashing worker, or generally are performed more or less than once.

Que's secondary goal is performance. It won't be able to match the speed or throughput of a dedicated queue, or perhaps even a Redis-backed queue, but it should be plenty fast for most use cases. It also includes a worker pool, so that multiple threads can process jobs in the same process. It can even do this in the background of your web process - if you're running on Heroku, for example, you won't need to run a separate worker dyno.

The rakefile includes a benchmark that compares the locking performance and concurrency of Que to that of DelayedJob and QueueClassic. On my i5 quad-core laptop, the results are along the lines of:

    ~/que $ rake benchmark
    Benchmarking 1000 jobs, 10 workers and synchronous_commit = on...
    Benchmarking delayed_job... 1000 jobs in 30.086127964 seconds = 33 jobs per second
    Benchmarking queue_classic... 1000 jobs in 19.642309724 seconds = 51 jobs per second
    Benchmarking que... 1000 jobs in 2.31483287 seconds = 432 jobs per second
    Benchmarking que_lateral... 1000 jobs in 2.383887915 seconds = 419 jobs per second

    ~/que $ SYNCHRONOUS_COMMIT=off rake benchmark
    Benchmarking 1000 jobs, 10 workers and synchronous_commit = off...
    Benchmarking delayed_job... 1000 jobs in 4.906474583 seconds = 204 jobs per second
    Benchmarking queue_classic... 1000 jobs in 1.587542394 seconds = 630 jobs per second
    Benchmarking que... 1000 jobs in 0.39063824 seconds = 2560 jobs per second
    Benchmarking que_lateral... 1000 jobs in 0.392068154 seconds = 2551 jobs per second

As always, this is a single naive benchmark that doesn't represent anything real, take it with a grain of salt, try it for yourself, etc.

**Que was extracted from an app of mine where it ran in production for a few months. It worked well, but it's been adapted somewhat from that design. Please don't trust it with your production data until you've tried to break it a few times.**

Right now, Que is only tested on Ruby 2.0 - it may work on other versions. It requires Postgres 9.2+ for the JSON type. The benchmark requires Postgres 9.3, since it also tests a variant of the typical locking query that uses the new LATERAL syntax.

## Installation

Add this line to your application's Gemfile:

    gem 'que'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install que

## Usage

The following is assuming you're using Rails 4.0. Que hasn't been tested with previous versions of Rails.

First, generate a migration for the jobs table.

    rails generate que:install
    rake db:migrate

Create a class for each type of job you want to run:

    # app/jobs/charge_credit_card.rb
    class ChargeCreditCard < Que::Job
      # Custom job options.
      @default_priority = 3
      @default_run_at = proc { 1.minute.from_now }

      def run(user_id, card_id)
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

Queue your job. Again, it's best to do this in a transaction with other changes you're making.

    ActiveRecord::Base.transaction do
      # Persist credit card information
      card = CreditCard.create(params[:credit_card])
      ChargeCreditCard.queue(current_user.id, card.id)
    end

You can also schedule it to run at a specific time, or with a specific priority:

    # 1 is high priority, 5 is low priority.
    ChargeCreditCard.queue current_user.id, card.id, :run_at => 1.day.from_now, :priority => 5

There are a few ways to work jobs. In development and production, the default is for Que to run a pool of workers to process jobs in their own background threads. If you like, you can disable this behavior when configuring your Rails app:

    config.que.mode = :off

You can also change the mode at any time with Que.mode = :off. The other options are :async and :sync. :async runs the background workers, while :sync will run any jobs you queue synchronously (that is, MyJob.queue runs the job immediately and won't return until it's completed). This makes your application's behavior easier to test, so it's the default in the test environment.

If you don't want to run workers in your web process, you can also work jobs in a rake task, similar to how other queueing systems work:

    # Run a pool of 4 workers.
    rake que:work

    # Or configure the number of workers.
    WORKER_COUNT=8 rake que:work

    # Run jobs one at a time. Useful if your app isn't thread-safe.
    rake que:work_single

If an error causes a job to fail, Que will repeat that job at intervals that increase exponentially with each error (using the same algorithm as DelayedJob). You can also hook Que into whatever error notification system you're using:

    config.que.error_handler = proc do |error|
      # Do whatever you want with the error object.
    end

## TODO

These aren't promises, just ideas for possible features:

  * Use LISTEN/NOTIFY to check for new jobs (or simpler, just wake a worker in the same process after a transaction commits a new job).
  * Multiple queues (in multiple tables?)
  * Integration with ActionMailer for easier mailings.
  * Add options for max_run_time and max_attempts. Make them specific to job classes.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
