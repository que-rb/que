## Multiple Queues

Que supports the use of multiple queues in a single job table. This feature is intended to support the case where multiple applications (with distinct codebases) are sharing the same database. For instance, you might have a separate Ruby application that handles only processing credit cards. In that case, you can run that application's workers against a specific queue:

```shell
que --queue-name credit_cards
```

Then you can set jobs to be enqueued in that queue specifically:

```ruby
ProcessCreditCard.enqueue current_user.id, :queue => 'credit_cards'

# Or:

class ProcessCreditCard < Que::Job
  # Set a default queue for this job class; this can be overridden by
  # passing the :queue parameter to enqueue like above.
  @queue = 'credit_cards'
end
```

In some cases, the ProcessCreditCard class may not be defined in the application that is enqueueing the job. In that case, you can specify the job class as a string:

```ruby
Que.enqueue current_user.id, :job_class => 'ProcessCreditCard', :queue => 'credit_cards'
```
