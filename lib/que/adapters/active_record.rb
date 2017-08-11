# frozen_string_literal: true

module Que
  module Adapters
    class ActiveRecord < Base
      def checkout
        checkout_activerecord_adapter { |conn| yield conn.raw_connection }
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
        ::ActiveRecord::Base.clear_active_connections!
      end

      private

      def checkout_activerecord_adapter(&block)
        # Use Rails' executor (if present) to make sure that the connection
        # we're using isn't taken from us while the block runs. See
        # https://github.com/chanks/que/issues/166#issuecomment-274218910
        if defined?(Rails.application.executor)
          Rails.application.executor.wrap do
            ::ActiveRecord::Base.connection_pool.with_connection(&block)
          end
        else
          ::ActiveRecord::Base.connection_pool.with_connection(&block)
        end
      end
    end
  end
end
