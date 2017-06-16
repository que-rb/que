# frozen_string_literal: true

module Que
  class Listener
    def initialize(pool:)
      @pool = pool
    end

    def listen
      @pool.checkout do |conn|
        @pool.execute "LISTEN que_listener_#{conn.backend_pid}"
      end
    end

    def wait_for_messages(timeout)
      # Make sure we never pass nil to this method, so we don't hang the thread.
      Que.assert(Numeric, timeout)

      output = {}

      @pool.checkout do |conn|
        loop do
          notification_received =
            conn.wait_for_notify(timeout) do |_, _, payload|
              # We've received at least one notification, so zero out the
              # timeout before we loop again to retrieve the next message. This
              # ensures that we don't wait an additional `timeout` seconds after
              # processing the final message before this method returns.
              timeout = 0

              # Be very defensive about the message we receive - it may not be
              # valid JSON, and may not have a message_type key.
              message =
                begin
                  Que.deserialize_json(payload)
                rescue JSON::ParserError
                end

              message_type = message && message.delete(:message_type)
              next unless message_type.is_a?(String)

              (output[message_type.to_sym] ||= []) << message
            end

          break unless notification_received
        end
      end

      output
    end

    def unlisten
      @pool.checkout do |conn|
        # Unlisten and drain notifications before releasing the connection.
        @pool.execute "UNLISTEN *"
        {} while conn.notifies
      end
    end
  end
end
