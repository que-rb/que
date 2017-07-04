# frozen_string_literal: true

# A helper method to manage transactions, used mainly by the migration system.
# It's available for general use, but if you're using an ORM that provides its
# own transaction helper, be sure to use that instead, or the two may interfere
# with one another.

module Que
  module Utils
    module Transactions
      def transaction
        pool.checkout do
          if pool.in_transaction?
            yield
          else
            begin
              execute "BEGIN"
              yield
            rescue => error
              raise
            ensure
              # Handle a raised error or a killed thread.
              if error || Thread.current.status == 'aborting'
                execute "ROLLBACK"
              else
                execute "COMMIT"
              end
            end
          end
        end
      end
    end
  end
end
