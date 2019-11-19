## Writing Reliable Jobs

Que does everything it can to ensure that jobs are worked exactly once, but if something bad happens when a job is halfway completed, there's no way around it - the job will need be repeated over again from the beginning, probably by a different worker. When you're writing jobs, you need to be prepared for this to happen.

The safest type of job is one that reads in data, either from the database or from external APIs, then does some number crunching and writes the results to the database. These jobs are easy to make safe - simply write the results to the database inside a transaction, and also destroy the job inside that transaction, like so:

```ruby
class UpdateWidgetPrice < Que::Job
  def run(widget_id)
    widget = Widget[widget_id]
    price  = ExternalService.get_widget_price(widget_id)

    ActiveRecord::Base.transaction do
      # Make changes to the database.
      widget.update price: price

      # Mark the job as destroyed, so it doesn't run again.
      destroy
    end
  end
end
```

Here, you're taking advantage of the guarantees of an [ACID](https://en.wikipedia.org/wiki/ACID) database. The job is destroyed along with the other changes, so either the write will succeed and the job will be run only once, or it will fail and the database will be left untouched. But even if it fails, the job can simply be retried, and there are no lingering effects from the first attempt, so no big deal.

The more difficult type of job is one that makes changes that can't be controlled transactionally. For example, writing to an external service:

```ruby
class ChargeCreditCard < Que::Job
  def run(user_id, credit_card_id)
    CreditCardService.charge(credit_card_id, amount: "$10.00")

    ActiveRecord::Base.transaction do
      User.where(id: user_id).update_all charged_at: Time.now
      destroy
    end
  end
end
```

What if the process abruptly dies after we tell the provider to charge the credit card, but before we finish the transaction? Que will retry the job, but there's no way to tell where (or even if) it failed the first time. The credit card will be charged a second time, and then you've got an angry customer. The ideal solution in this case is to make the job [idempotent](https://en.wikipedia.org/wiki/Idempotence), meaning that it will have the same effect no matter how many times it is run:

```ruby
class ChargeCreditCard < Que::Job
  def run(user_id, credit_card_id)
    unless CreditCardService.check_for_previous_charge(credit_card_id)
      CreditCardService.charge(credit_card_id, amount: "$10.00")
    end

    ActiveRecord::Base.transaction do
      User.where(id: user_id).update_all charged_at: Time.now
      destroy
    end
  end
end
```

This makes the job slightly more complex, but reliable (or, at least, as reliable as your credit card service).

Finally, there are some jobs where you won't want to write to the database at all:

```ruby
class SendVerificationEmail < Que::Job
  def run(email_address)
    Mailer.verification_email(email_address).deliver
  end
end
```

In this case, we don't have a way to prevent the occasional double-sending of an email. But, for ease of use, you can leave out the transaction and the `destroy` call entirely - Que will recognize that the job wasn't destroyed and will clean it up for you.

### Timeouts

Long-running jobs aren't necessarily a problem for the database, since the overhead of an individual job is very small (just an advisory lock held in memory). But jobs that hang indefinitely can tie up a worker and [block the Ruby process from exiting gracefully](https://github.com/que-rb/que/blob/master/docs/shutting_down_safely.md), which is a pain.

If there's part of your job that is prone to hang (due to an API call or other HTTP request that never returns, for example), you can (and should) timeout those parts of your job. For example, consider a job that needs to make an HTTP request and then write to the database:

```ruby
class ScrapeStuff < Que::Job
  def run(url_to_scrape)
    result = YourHTTPLibrary.get(url_to_scrape)

    ActiveRecord::Base.transaction do
      # Insert result...

      destroy
    end
  end
end
```

That request could take a very long time, or never return at all. Let's use the timeout feature that almost all HTTP libraries offer some version of:

```ruby
class ScrapeStuff < Que::Job
  def run(url_to_scrape)
    result = YourHTTPLibrary.get(url_to_scrape, timeout: 5)

    ActiveRecord::Base.transaction do
      # Insert result...

      destroy
    end
  end
end
```

Now, if the request takes more than five seconds, an error will be raised (probably - check your library's documentation) and Que will just retry the job later.
