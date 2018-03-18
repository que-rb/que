## Using Que With ActiveJob

You can include `Que::ActiveJob::JobExtensions` into your `ApplicationJob` subclass to get support for all of Que's 
[helper methods](/docs/job_helper_methods.md). These methods will become no-ops if you use a queue adapter that isn't Que, so if you like to use a different adapter in development they shouldn't interfere.

Additionally, including `Que::ActiveJob::JobExtensions` lets you define a run() method that supports keyword arguments.
