## Command Line Interface

```
usage: que [options] [file/to/require] ...
    -h, --help                       Show this help text.
    -i, --poll-interval [INTERVAL]   Set maximum interval between polls for available jobs, in seconds (default: 5)
    -l, --log-level [LEVEL]          Set level at which to log to STDOUT (debug, info, warn, error, fatal) (default: info)
    -q, --queue-name [NAME]          Set a queue name to work jobs from. Can be passed multiple times. (default: the default queue only)
    -v, --version                    Print Que version and exit.
    -w, --worker-count [COUNT]       Set number of workers in process (default: 6)
        --log-internals              Log verbosely about Que's internal state. Only recommended for debugging issues
        --maximum-queue-size [SIZE]  Set maximum number of jobs to be cached in this process awaiting a worker (default: 8)
        --minimum-queue-size [SIZE]  Set minimum number of jobs to be cached in this process awaiting a worker (default: 2)
        --wait-period [PERIOD]       Set maximum interval between checks of the in-memory job queue, in milliseconds (default: 50)
        --worker-priorities [LIST]   List of priorities to assign to workers, unspecified workers take jobs of any priority (default: 10,30,50)
```

Some explanation of options:

### connection-url

### poll-interval

### minimum-queue-size and maximum-queue-size

### wait-period

### worker-priorities
