# frozen_string_literal: true

module Que
  module Adapters
    class ActiveRecord < Base
      def checkout
        checkout_activerecord_adapter do |conn|
          yield conn.raw_connection
        end
      end

      def wake_worker_after_commit
        # Works with ActiveRecord 3.2 and 4 (possibly earlier, didn't check)
        if in_transaction?
          checkout_activerecord_adapter { |adapter| adapter.add_transaction_record(TransactionCallback.new) }
        else
          Que.wake!
        end
      end

      def cleanup!
        # ActiveRecord will check out connections to the current thread when
        # queries are executed and not return them to the pool until
        # explicitly requested to. The wisdom of this API is questionable, and
        # it doesn't pose a problem for the typical case of workers using a
        # single PG connection (since we ensure that connection is checked in
        # and checked out responsibly), but since ActiveRecord supports
        # connections to multiple databases, it's easy for people using that
        # feature to unknowingly leak connections to other databases. So, take
        # the additional step of telling ActiveRecord to check in all of the
        # current thread's connections between jobs.
        Thread.current[:que_activerecord_connection] = nil
        ::ActiveRecord::Base.clear_active_connections!
      end

      class TransactionCallback
        def has_transactional_callbacks?
          true
        end

        def rolledback!(force_restore_state = false, should_run_callbacks = true)
          # no-op
        end

        def committed!(should_run_callbacks = true)
          Que.wake!
        end

        def before_committed!(*)
          # no-op
        end

        def add_to_transaction
          # no-op.
          #
          # This is called when we're in a nested transaction. Ideally we would
          # `wake!` when the outer transaction gets committed, but that would be
          # a bigger refactor!
        end
      end

      private

      def checkout_activerecord_adapter(&block)
        Thread.current[:que_activerecord_connection] ||= ::ActiveRecord::Base.connection
        block.call(Thread.current[:que_activerecord_connection])
      end
    end
  end
end
