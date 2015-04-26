## Writing Reliable Jobs

Que does everything it can to ensure that jobs are worked exactly once, but if something bad happens when a job is halfway completed, there's no way around it - the job will need be repeated over again from the beginning, probably by a different worker. When you're writing jobs, you need to be prepared for this to happen.

The safest type of job is one that reads in data, either from the database or from external APIs, then does some number crunching and writes the results to the database. These jobs are easy to make safe - simply write the results to the database inside a transaction, and also have the job destroy itself inside that transaction, like so:

```ruby
class UpdateWidgetPrice < Que::Job
  def run(widget_id)
    widget = Widget[widget_id]
    price  = ExternalService.get_widget_price(widget_id)

    ActiveRecord::Base.transaction do
      # Make changes to the database.
      widget.update :price => price

      # Destroy the job.
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
    CreditCardService.charge(credit_card_id, :amount => "$10.00")

    ActiveRecord::Base.transaction do
      User.where(:id => user_id).update_all :charged_at => Time.now
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
      CreditCardService.charge(credit_card_id, :amount => "$10.00")
    end

    ActiveRecord::Base.transaction do
      User.where(:id => user_id).update_all :charged_at => Time.now
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

In this case, we don't have any no way to prevent the occasional double-sending of an email. But, for ease of use, you can leave out the transaction and the `destroy` call entirely - Que will recognize that the job wasn't destroyed and will clean it up for you.

### Timeouts

Long-running jobs aren't necessarily a problem in Que, since the overhead of an individual job isn't that big (just an open PG connection and an advisory lock held in memory). But jobs that hang indefinitely can tie up a worker and [block the Ruby process from exiting gracefully](https://github.com/chanks/que/blob/master/docs/shutting_down_safely.md), which is a pain.

Que doesn't offer a general way to kill jobs that have been running too long, because that currently can't be done safely in Ruby. Typically, one would use Ruby's Timeout module for this sort of thing, but wrapping a database transaction inside a timeout introduces a risk of premature commits, which can corrupt your data. See [here](http://blog.headius.com/2008/02/ruby-threadraise-threadkill-timeoutrb.html) and [here](http://coderrr.wordpress.com/2011/05/03/beware-of-threadkill-or-your-activerecord-transactions-are-in-danger-of-being-partially-committed/) for detail on why this is.

However, if there's part of your job that is prone to hang (due to an API call or other HTTP request that never returns, for example), you can timeout those individual parts of your job relatively safely. For example, consider a job that needs to make an HTTP request and then write to the database:

```ruby
require 'net/http'

class ScrapeStuff < Que::Job
  def run(domain_to_scrape, path_to_scrape)
    result = Net::HTTP.get(domain_to_scrape, path_to_scrape)

    ActiveRecord::Base.transaction do
      # Insert result...

      destroy
    end
  end
end
```

That request could take a very long time, or never return at all. Let's wrap it in a five-second timeout:

```ruby
require 'net/http'
require 'timeout'

class ScrapeStuff < Que::Job
  def run(domain_to_scrape, path_to_scrape)
    result = Timeout.timeout(5){Net::HTTP.get(domain_to_scrape, path_to_scrape)}

    ActiveRecord::Base.transaction do
      # Insert result...

      destroy
    end
  end
end
```

Now, if the request takes more than five seconds, a `Timeout::Error` will be raised and Que will just retry the job later. This solution isn't perfect, since Timeout uses Thread#kill under the hood, which can lead to unpredictable behavior. But it's separate from our transaction, so there's no risk of losing data - even a catastrophic error that left Net::HTTP in a bad state would be fixable by restarting the process.

Finally, remember that if you're using a library that offers its own timeout functionality, that's usually preferable to using the Timeout module.
