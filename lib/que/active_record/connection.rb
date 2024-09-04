# frozen_string_literal: true

module Que
  module ActiveRecord
    class << self
      def active_rails_executor?
        defined?(::Rails.application.executor) && ::Rails.application.executor.active?
      end

      def wrap_in_rails_executor(&block)
        if defined?(::Rails.application.executor)
          ::Rails.application.executor.wrap(&block)
        else
          yield
        end
      end
    end

    module Connection
      class << self
        private

        # Check out a PG::Connection object from ActiveRecord's pool.
        def checkout
          # Use Rails' executor (if present) to make sure that the connection
          # we're using isn't taken from us while the block runs. See
          # https://github.com/que-rb/que/issues/166#issuecomment-274218910
          Que::ActiveRecord.wrap_in_rails_executor do
            ::ActiveRecord::Base.connection_pool.with_connection do |conn|
               yield conn.raw_connection
            end
          end
        end
      end

      module JobMiddleware
        class << self
          def call(job)
            # Use Rails' executor (if present) to make sure that the connection
            # used by the job isn't returned to the pool prematurely. See
            # https://github.com/que-rb/que/issues/411
            Que::ActiveRecord.wrap_in_rails_executor do
              yield
            end

            clear_active_connections_if_needed!(job)
          end

          private

          # ActiveRecord will check out connections to the current thread when
          # queries are executed and not return them to the pool until
          # explicitly requested to. I'm not wild about this API design, and
          # it doesn't pose a problem for the typical case of workers using a
          # single PG connection (since we ensure that connection is checked
          # in and checked out responsibly), but since ActiveRecord supports
          # connections to multiple databases, it's easy for people using that
          # feature to unknowingly leak connections to other databases. So,
          # take the additional step of telling ActiveRecord to check in all
          # of the current thread's connections after each job is run.
          def clear_active_connections_if_needed!(job)
            # don't clean in synchronous mode
            # see https://github.com/que-rb/que/pull/393
            return if job.class.resolve_que_setting(:run_synchronously)

            # don't clear connections in nested jobs executed synchronously
            # i.e. while we're still inside of the rails executor
            # see https://github.com/que-rb/que/pull/412#issuecomment-2194412783
            return if Que::ActiveRecord.active_rails_executor?

            ::ActiveRecord::Base.clear_active_connections!
          end
        end
      end
    end
  end
end
