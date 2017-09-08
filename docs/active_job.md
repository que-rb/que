## Using Que With ActiveJob

You can include `Que::ActiveJob::JobExtensions` into your `ApplicationJob` subclass to get support for all of Que's job methods.

Recommend using numeric priorities over named queues, again.
