## Managing Workers

Que provides a pool of workers to process jobs in a multithreaded fashion - this allows you to save memory by working many jobs simultaneously in the same process.

When the worker pool is active (as it is by default when running `rails server`, or when you set Que.mode = :async), the default number of workers is 4. This is fine for most use cases, but the ideal number for your app will depend on your interpreter and what types of jobs you're running.

Ruby MRI has a global interpreter lock (GIL), which prevents it from using more than one CPU core at a time. Having multiple workers running makes sense if your jobs tend to spend a lot of time in I/O (waiting on complex database queries, sending emails, making HTTP requests, etc.), as most jobs do. However, if your jobs are doing a lot of work in Ruby, they'll be spending a lot of time blocking each other, and having too many workers running will just slow everything down.

JRuby and Rubinius, on the other hand, have no global interpreter lock, and so can make use of multiple CPU cores - you could potentially set the number of workers very high for them. You should experiment to find the best setting for your use case.

You can change the number of workers in the pool whenever you like by setting the `worker_count` option:

    Que.worker_count = 8

    # Or, in your Rails configuration:
    config.que.worker_count = 8

### Working Jobs Via Rake Task

If you don't want to burden your web processes with too much work and want to run workers in a background process instead, similar to how most other queues work, you can:

    # Run a pool of 4 workers:
    rake que:work

    # Or configure the number of workers:
    WORKER_COUNT=8 rake que:work

### Thread-Unsafe Application Code

If your application code is not thread-safe, you won't want any workers to be processing jobs while anything else is happening in the Ruby process. So, you'll want to turn the worker pool off by default:

    Que.mode = :off

    # Or, in your Rails configuration:
    config.que.mode = :off

This will prevent Que from trying to process jobs in the background of your web processes. In order to actually work jobs, you'll want to run a single worker at a time, and to do so via a separate rake task, like so:

    WORKER_COUNT=1 rake que:work

### The Wake Interval

If a worker checks the job queue and finds no jobs ready for it to work, it will fall asleep. In order to make sure that newly-available jobs don't go unworked, a worker is awoken every so often to check for available work. By default, this happens every five seconds, but you can make it happen more or less often by setting a custom wake_interval:

    Que.wake_interval = 2

    # Or, in your Rails configuration:
    config.que.wake_interval = 2   # 2.seconds also works fine.

You can also choose to never let workers wake up on their own:

    # Never wake up any workers:
    Que.wake_interval = nil

If you do this, though, you'll need to wake workers manually.

### Manually Waking Workers

Regardless of the `wake_interval` setting, you can always wake workers manually:

    # Wake up a single worker to check the queue for work:
    Que.wake!

    # Wake up all workers in this process to check for work:
    Que.wake_all!

`Que.wake_all!` is helpful if there are no jobs available and all your workers go to sleep, and then you queue a large number of jobs. Typically, it will take a little while for the entire pool of workers get going again - a new one will wake up every `wake_interval` seconds, but it will take up to `wake_interval * worker_count` seconds for all of them to get going. `Que.wake_all!` can get them all moving immediately.
