## Writing Reliable Jobs

Que does everything it can to ensure that jobs are worked exactly once, but if something bad happens when a job is halfway completed, there's no way around it - the job will need be repeated over again from the beginning, probably by a different worker. When you're writing jobs, you need to be prepared for this to happen.

The safest type of job is one that reads in data, either from the database or from external APIs, then does some number crunching and writes the results to the database. These jobs are easy to make safe: simply write the results to the database inside a transaction, and also have the job destroy itself inside that transaction, like so:

    class UpdateWidgetPrice < Que::Job
      def run(widget_id)
        widget = Widget.where(:widget_id => widget_id).first
        price  = ExternalService.get_widget_price(widget_id)

        ActiveRecord::Base.transaction do
          # Make changes to the database.
          widget.update :price => price

          # Destroy the job.
          destroy
        end
      end
    end

Here, you're taking advantage of the guarantees of a transactional database. The job is destroyed along with the other changes, so either the job will succeed and be run only once, or it will fail at some point and simply be retried. But even if it has to be retried, the changes won't be made twice, so no big deal.

The more difficult type of job is one that makes changes that can't be controlled transactionally. For example, making changes to an external service:

    class ChargeCreditCard < Que::Job
      def run(user_id, credit_card_id)
        CreditCardProvider.charge(credit_card_id, :amount => "$10.00")

        ActiveRecord::Base.transaction do
          User.where(:id => user_id).update :charged_at => Time.now
          destroy
        end
      end
    end

What if the process segfaults after we tell the provider to charge the credit card, but before we finish the transaction? There's no way for Que to know where the job failed, so it will be retried, charge the credit card a second time, and then you've got an angry customer. The ideal solution in this case is to make the job idempotent, meaning that it will have the same effect no matter how many times it is run:

    class ChargeCreditCard < Que::Job
      def run(user_id, credit_card_id)
        unless CreditCardProvider.check_for_previous_charge(credit_card_id)
          CreditCardProvider.charge(credit_card_id, :amount => "$10.00")
        end

        ActiveRecord::Base.transaction do
          User.where(:id => user_id).update_all :charged_at => Time.now
          destroy
        end
      end
    end

This makes the job slightly more complex, but solves the problem. Note that while Que can't guarantee that the same job won't be worked more than once, it can guarantee that it won't be worked more than once simultaneously, so we don't need to worry about a race condition here (wherein two workers would simultaneously check for a previous charge, see that there isn't one, and then each make their own charges).

Finally, there are some jobs where you won't want to write to the database at all:

    class SendVerificationEmail < Que::Job
      def run(email_address)
        Mailer.verification_email(email_address).deliver
      end
    end

In this case, we don't have any no way to prevent the occasional double-sending of an email. But for ease of use, you can leave out the transaction entirely - Que will recognize that the job wasn't destroyed and will clean it up for you.
