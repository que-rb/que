## Managing Workers

Que uses a multithreaded pool of workers to run jobs in parallel - this allows you to save memory by working many jobs simultaneously in the same process. The `que` executable starts up a pool of 6 workers by default. This is fine for most use cases, but the ideal number for your app will depend on your interpreter and what types of jobs you're running.

Ruby MRI has a global interpreter lock (GIL), which prevents it from using more than one CPU core at a time. Having multiple workers running makes sense if your jobs tend to spend a lot of time in I/O (waiting on complex database queries, sending emails, making HTTP requests, etc.), as most jobs do. However, if your jobs are doing a lot of work in Ruby, they'll be spending a lot of time blocking each other, and having too many workers running will just slow everything down. So, you'll want to choose the appropriate number of workers for your use case.

### Working Jobs Via Executable

```shell
# Run a pool of 6 workers:
que

# Or configure the number of workers:
que --worker-count 10
```

See `que -h` for a list of command-line options.

### Thread-Unsafe Application Code

If your application code is not thread-safe, you won't want any workers to be processing jobs while anything else is happening in the Ruby process. So, you'll want to run a single worker at a time, like so:

```shell
que --worker-count 1
```
