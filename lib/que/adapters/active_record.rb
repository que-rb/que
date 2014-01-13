module Que
  module Adapters
    class ActiveRecord < Base
      def checkout
        ::ActiveRecord::Base.connection_pool.with_connection do |conn|
          @conn = conn
          yield @conn.raw_connection
        end
      end

      def wake_worker_after_commit
        # Works with ActiveRecord 3.2 and 4 (possibly earlier, didn't check)
        if @conn.raw_connection.transaction_status != PGconn::PQTRANS_IDLE
          @conn.add_transaction_record(CommittedCallback.new)
        else
          Que.wake!
        end
      end

      class CommittedCallback
        def has_transactional_callbacks?
          true
        end
        def logger
          Logger.new(STDOUT) # for debugging
        end
        def committed!
          Que.wake!
        end
      end
    end
  end
end
