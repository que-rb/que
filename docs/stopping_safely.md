## Stopping Safely

Que's primary goal is reliability, but this can be difficult to accomplish when a Ruby process is exiting. When a Ruby process exits, all threads (other than the main one) are killed with Thread#kill. Thread#kill will stop normal operation as an error would, except it doesn't trigger rescue blocks. However, it DOES trigger ensure blocks. This is a problem because ActiveRecord and Sequel (and probably other ORMs) have transaction logic that looks like this (but more complex):

    def transaction
      execute "BEGIN"
      yield
    rescue Exception => error
      execute "ROLLBACK"
    ensure
      execute "COMMIT" unless error
    end

If a worker thread is killed while inside the transaction, Ruby will skip the ROLLBACK and jump straight to the COMMIT, which can have disastrous consequences. Imagine a banking application written in Ruby:

    database.transaction do
      # Take $50 out of Alice's account.
      execute "UPDATE accounts SET amount = amount - 50 WHERE user_id = 1"

      # Add $50 to Bob's account.
      execute "UPDATE accounts SET amount = amount + 50 WHERE user_id = 2"
    end

If an error occurs in the database between the two account changes, the transaction will roll back, and no harm done. However, if the Ruby thread running the transaction block is killed between the two changes, the rescue block is not run and the ensure block is, and the transaction is committed prematurely. The database sees:

    BEGIN;
    UPDATE accounts SET amount = amount - 50 WHERE user_id = 1;
    COMMIT;

This is bad. If we want our application to be reliable, we need to be very careful in how we shut down the process.

### Safe Shutdown

When a worker is shut down, either by setting `Que.mode = :off` or by lowering `Que.worker_count`, Que sets a flag in it that tells it to stop picking up new jobs and to shut down. Workers check for this flag after every job they process, so the worker will stop safely after it finishes the job it is currently running.

### Rapid Shutdown (Que.stop!)

Unfortunately, some jobs may run for long periods of time, and there's no way for Que to determine how long it will take for a job it is running to finish properly. But the process may need to shut down immediately. For that case, Que provides `Que.stop!`, which raises an Interrupt (a type of error that isn't caught by plain rescue blocks, but is caught by the block in the transaction implementation above) in each worker's thread, rolling back any open transactions.

This technique isn't foolproof or without its drawbacks. When you use Thread#raise, you're interfering in the thread's operation without any idea of where it is or what it's doing. This can have unpredictable consequences - for example, if the worker thread is running a database query at the moment the error is raised, that particular connection may be left in an unusable state. For this reason, we don't use `Que.stop!` unless the Ruby process is about to end anyway.

### Signal Handling

On Heroku, for example, a dyno will be shut down by first being sent SIGTERM, and then SIGKILL ten seconds later if they have failed to stop on their own.

If you're setting up your own signal handlers (in a custom rake task, for example), it would be a good idea to test their behavior before putting them into production. You may want to look at `que/tasks/safe_shutdown.rb` for ideas on how to test this.

### Job-Approved Shutdown

So, you have a long-running job (more than 10 seconds), and you want to decrease the risk of it being half-completed due to blindly-raised exceptions. In this case, it's a good practice to let Que know when would be a good place to stop. Consider this example:

    class LongRunningJob < Que::Job
      def run
        results = []

        1000.times do
          results << ExternalService.make_http_get_request_that_may_take_a_while
        end

        ActiveRecord::Base.transaction do
          # Insert the stuff you retrieved
          destroy
        end
      end
    end

This job does a whole bunch of reads that take up the bulk of the processing time, and then only persist results to the database at the very end. So, this job could be safely canceled in 

    1000.times do
      results << ExternalService.make_http_get_request_that_may_take_a_while
      safe_to_stop
    end
