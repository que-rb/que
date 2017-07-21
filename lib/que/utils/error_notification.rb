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
          notifier.call(*args)
        end
      rescue => error
        Que.log(
          event: :error_notifier_failed,
          level: :error,
          message: "error_notifier callable raised an error",
          error_message: error.message,
          error_backtrace: error.backtrace,
        )
        nil
      end

      MAXIMUM_QUEUE_SIZE = 5
      ASYNC_QUEUE  = Queue.new
      ASYNC_THREAD = Thread.new { loop { Que.notify_error(*ASYNC_QUEUE.pop) } }
      ASYNC_THREAD.abort_on_exception = true

      # Helper method to notify errors asynchronously. For use in high-priority
      # code, where we don't want to be held up by whatever I/O the error
      # notification proc contains.

      # We don't synchronize around the size check and the push, so there's a
      # race condition where the queue could grow to more than
      # MAXIMUM_QUEUE_SIZE errors, but that's not really a huge concern. The
      # size check is mainly here to ensure that the error queue doesn't grow
      # unboundedly large in pathological cases.

      def notify_error_async(*args)
        if ASYNC_QUEUE.size < MAXIMUM_QUEUE_SIZE
          ASYNC_QUEUE.push(args)
          true
        else
          false
        end
      end
    end
  end
end
