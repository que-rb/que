## Customizing Que

One of Que's goals to be easily extensible and hackable (and if anyone has any suggestions on ways to accomplish that, please [open an issue](https://github.com/chanks/que/issues)). This document is meant to demonstrate some of the ways Que can be used to accomplish different tasks that it's not already designed for.

### DelayedJob-style Jobs

DelayedJob offers a simple API for delaying methods to objects:

    @user.delay.activate!(@device)

The API is pleasant, but implementing it requires storing marshalled Ruby objects in the database, which is both inefficient and prone to bugs - for example, if you deploy an update that changes the name of an instance variable (a contained, internal change that might seem completely innocuous), the marshalled objects in the database will retain the old instance variable name and will behave unexpectedly when unmarshalled into the new Ruby code.

This is the danger of mixing the ephemeral state of a Ruby object in memory with the more permanent state of a database row. The advantage of Que's API is that, since your arguments are forced through a JSON serialization/deserialization process, it becomes your responsibility when designing a job class to establish an API for yourself (what the arguments to the job are and what they mean) that you will have to stick to in the future.

That said, if you want to queue jobs in the DelayedJob style, that can be done relatively easily:

    class Delayed < Que::Job
      def run(receiver, method, args)
        Marshal.load(receiver).send method, *Marshal.load(args)
      end
    end

    class DelayedAction
      def initialize(receiver)
        @receiver = receiver
      end

      def method_missing(method, *args)
        Delayed.enqueue Marshal.dump(@receiver), method, Marshal.dump(args)
      end
    end

    class Object
      def delay
        DelayedAction.new(self)
      end
    end

You can replace Marshal with YAML if you like.

### QueueClassic-style Jobs

You may find it a hassle to keep an individual class file for each type of job. QueueClassic has a simpler design, wherein you simply give it a class method to call, like:

    QC.enqueue("Kernel.puts", "hello world")

You can mimic this style with Que by using a simple job class:

    class Command < Que::Job
      def run(method, *args)
        receiver, message = method.split('.')
        Object.const_get(receiver).send(message, *args)
      end
    end

    # Then:

    Command.enqueue "Kernel.puts", "hello world"

### Retaining Finished Jobs

Que deletes jobs from the queue as they are worked, in order to keep the `que_jobs` table and index small and efficient. If you have a need to hold onto finished jobs, the recommended way to do this is to add a second table to hold them, and then insert them there as they are deleted from the queue. You can use Ruby's inheritance mechanics to do this cleanly:

    Que.execute "CREATE TABLE finished_jobs AS SELECT * FROM que_jobs LIMIT 0"
    # Or, better, use a proper CREATE TABLE with not-null constraints, and add whatever indexes you like.

    class MyJobClass < Que::Job
      def destroy
        Que.execute "INSERT INTO finished_jobs SELECT * FROM que_jobs WHERE queue = $1::text AND priority = $2::integer AND run_at = $3::timestamptz AND job_id = $4::bigint", @attrs.values_at(:queue, :priority, :run_at, :job_id)
        super
      end
    end

Then just have your job classes inherit from MyJobClass instead of Que::Job. If you need to query the jobs table and you want to include both finished and unfinished jobs, you might use:

    Que.execute "CREATE VIEW all_jobs AS SELECT * FROM que_jobs UNION ALL SELECT * FROM finished_jobs"
    Que.execute "SELECT * FROM all_jobs"

Alternately, if you want a more foolproof solution and you're not scared of PostgreSQL, you can use a trigger:

    CREATE FUNCTION please_save_my_job()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
      BEGIN
        INSERT INTO finished_jobs SELECT (OLD).*;
        RETURN OLD;
      END;
    $$;

    CREATE TRIGGER keep_all_my_old_jobs BEFORE DELETE ON que_jobs FOR EACH ROW EXECUTE PROCEDURE please_save_my_job();

### Additional Job Information

Que supports non-standard structures for the jobs table. For example, if you want each of your jobs reference rows in another table, you can add a foreign key:

    CREATE TABLE widgets (
      id serial primary key,
      name text
    );

    ALTER TABLE que_jobs
      ADD COLUMN widget_id integer REFERENCES widgets ON DELETE RESTRICT;

Then simply INSERT rows into the que_jobs table with widget_ids and they'll be available in the job's attributes hash:

    class ProcessWidget < Que::Job
      def run(*args)
        widget = Widget.find(@attrs[:widget_id])
        widget.process!
      end
    end

This is useful if you want to make sure that, for example, widgets aren't deleted before they've been processed. Remember that it may or may not be a good idea to index the widget_id column, depending on your use case.
