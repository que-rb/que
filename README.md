# Que

A job queue that uses Postgres' advisory lock system. The aim is for job queuing to be efficient and highly concurrent (there's no need for a locked_at column or SELECT FOR UPDATE NOWAIT queries) but still very durable (with all the stability that Postgres offers).

It was extracted from an app of mine where it worked well for me, but I wouldn't recommend anyone use it until it's generalized some more. It currently requires the use of Sequel as an ORM, but I expect that it could be expanded to support ActiveRecord.

Features:
  * Jobs can be queued transactionally, alongside every other change to your database.
  * If a worker process crashes or segfaults, the jobs it was working are immediately released to be picked up by other workers.
  * Workers are multi-threaded, similar to Sidekiq, so the same process can work many jobs at the same time.
  * Workers can run in your web processes. This means if you're on Heroku, there's no need to have a worker process constantly running.

## Installation

Add this line to your application's Gemfile:

    gem 'que'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install que

## Usage

Create a jobs table that looks something like:

    CREATE TABLE jobs
    (
      priority integer NOT NULL,
      run_at timestamp with time zone NOT NULL DEFAULT now(),
      job_id bigserial NOT NULL,
      created_at timestamp with time zone NOT NULL DEFAULT now(),
      type text NOT NULL,
      args json NOT NULL DEFAULT '[]'::json,
      data json NOT NULL DEFAULT '{}'::json,
      CONSTRAINT jobs_pkey PRIMARY KEY (priority, run_at, job_id),
      CONSTRAINT valid_priority CHECK (priority >= 1 AND priority <= 5)
    );

Start up the worker to process jobs:

    # In an initializer:
    Que::Worker.state = :async

    # Alternatively, you can set state to :sync to process jobs in the same
    # thread as they're queued, which is useful for testing, or set it to :off
    # to simply leave them in the jobs table.

Create a class for each type of job you want to run:

    class ChargeCreditCard < Que::Job
      @default_priority = 1 # Highest priority.

      def perform(user_id, card_id)
        # Do stuff.

        db.transaction do
          # Write any changes you'd like to the database.

          # It's best to destroy the job in the same transaction as any other
          # changes you make. Que will destroy the job for you after the
          # perform method if you don't do it here, but if your job writes to
          # the DB but doesn't destroy the job in the same transaction, it's
          # possible that the job could be repeated in the event of a crash.
          destroy
        end
      end
    end

Queue that type of job. Again, it's best to take advantage of Postgres by doing this in a transaction with other changes you're making:

    DB.transaction do
      # Persist credit card information
      card = CreditCard.create(params[:credit_card])
      ChargeCreditCard.queue(current_user.id, card.id)
    end

## TODO

These aren't promises, just ideas for stuff that could be done in the future.

  * Railtie, to make default setup easy.
  * ActiveRecord support.
  * Keep deleted jobs.
  * Use LISTEN/NOTIFY for checking for new jobs, rather than signaling the worker within the same process.
  * Multiple queues (in multiple tables?)
  * More configurable logging that isn't tied to Rails.
  * Integration with ActionMailer for easier mailings.
  * Options for max_run_time and max_attempts that are specific to job classes.
  * Rake tasks for creating/working/dropping/clearing queues.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
