# frozen_string_literal: true

module Que
  module Utils
    module ErrorNotification
      attr_accessor :error_notifier

      def notify_error(*args)
        Que.internal_log(:error_notification_attempted) do
          {args: args.inspect}
        end

        if notifier = error_notifier
          arity = notifier.arity
          args = args.first(arity) if arity >= 0

          notifier.call(*args)
        end
      rescue => error
        Que.log(
          event:   :error_notifier_failed,
          level:   :error,
          message: "error_notifier callable raised an error",

          error_class:     error.class.name,
          error_message:   error.message,
          error_backtrace: error.backtrace,
        )
        nil
      end

      ASYNC_QUEUE    = Queue.new
      MAX_QUEUE_SIZE = 5

      # Helper method to notify errors asynchronously. For use in high-priority
      # code, where we don't want to be held up by whatever I/O the error
      # notification proc contains.
      def notify_error_async(*args)
        # We don't synchronize around the size check and the push, so there's a
        # race condition where the queue could grow to more than the maximum
        # number of errors, but no big deal if it does. The size check is mainly
        # here to ensure that the error queue doesn't grow unboundedly large in
        # pathological cases.

        if ASYNC_QUEUE.size < MAX_QUEUE_SIZE
          ASYNC_QUEUE.push(args)
          # Puma raises some ugly warnings if you start up a new thread in the
          # background during initialization, so start the async error-reporting
          # thread lazily.
          async_error_thread
          true
        else
          false
        end
      end

      def async_error_thread
        CONFIG_MUTEX.synchronize do
          @async_error_thread ||=
            Thread.new do
              Thread.current.abort_on_exception = true
              loop { Que.notify_error(*ASYNC_QUEUE.pop) }
            end
        end
      end
    end
  end
end
