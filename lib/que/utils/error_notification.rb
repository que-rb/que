# frozen_string_literal: true

module Que
  module Utils
    module ErrorNotification
      attr_accessor :error_notifier

      def notify_error(*args)
        if notifier = error_notifier
          notifier.call(*args)
        end
      rescue => error
        Que.log(
          level: :error,
          message: "error_notifier callable raised an error",
          error_message: error.message,
          error_backtrace: error.backtrace,
        )
        nil
      end
    end
  end
end
