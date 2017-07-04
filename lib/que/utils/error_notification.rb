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
        # Log loudly and swallow the error.
      end
    end
  end
end
