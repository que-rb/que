# frozen_string_literal: true

module Que
  class Listener
    MESSAGE_CALLBACKS = Utils::Registrar.new(raise_on_missing: false)
    MESSAGE_FORMATS   = Utils::Registrar.new(raise_on_missing: false, &:freeze)

    def initialize(pool:, channel: nil)
      @pool    = pool
      @channel = channel

      Que.internal_log :listener_instantiate, self do
        {
          # TODO: backend_pid: connection.backend_pid,
        }
      end
    end

    def listen
      @pool.checkout do |conn|
        @pool.execute "LISTEN #{@channel || "que_listener_#{conn.backend_pid}"}"
      end
    end

    def wait_for_messages(timeout)
      # Make sure we never pass nil to this method, so we don't hang the thread.
      Que.assert(Numeric, timeout)

      Que.internal_log :listener_waiting, self do
        {
          # TODO: backend_pid: connection.backend_pid,
          timeout: timeout,
        }
      end

      output = {}

      @pool.checkout do |conn|
        loop do
          notification_received =
            conn.wait_for_notify(timeout) do |channel, pid, payload|
              Que.internal_log(:listener_received_notification, self) do
                {
                  channel: channel,
                  # TODO: backend_pid: connection.backend_pid,
                  source_pid: pid,
                  payload: payload,
                }
              end

              # We've received at least one notification, so zero out the
              # timeout before we loop again to retrieve the next message. This
              # ensures that we don't wait an additional `timeout` seconds after
              # processing the final message before this method returns.
              timeout = 0

              # Be very defensive about the message we receive - it may not be
              # valid JSON, and may not have a message_type key.
              messages = parse_payload(payload)

              next unless messages

              unless messages.is_a?(Array)
                messages = [messages]
              end

              messages.each do |message|
                message_type = message && message.delete(:message_type)
                next unless message_type.is_a?(String)

                (output[message_type.to_sym] ||= []) << message
              end
            end

          break unless notification_received
        end
      end

      return output if output.empty?

      Que.internal_log(:listener_received_messages, self) { {messages: output} }

      output.each do |type, messages|
        if callback = MESSAGE_CALLBACKS[type]
          messages.select! do |message|
            begin
              callback.call(message)
              true
            rescue => error
              Que.notify_error_async(error)
              false
            end
          end
        end

        if format = MESSAGE_FORMATS[type]
          messages.select! do |m|
            if message_matches_format?(m, format)
              true
            else
              message = [
                "Message of type '#{type}' doesn't match format!",
                "Message: #{m.inspect}",
                "Format: #{format.inspect}",
              ].join("\n")

              Que.notify_error_async(Error.new(message))
              false
            end
          end
        end

        messages.each(&:freeze)
      end

      output.delete_if { |_, messages| messages.empty? }

      Que.internal_log(:listener_processed_messages, self) { {messages: output} }

      output
    end

    def unlisten
      @pool.checkout do |conn|
        # Unlisten and drain notifications before releasing the connection.
        @pool.execute "UNLISTEN *"
        conn.drain_notifications
      end

      Que.internal_log :listener_unlisten, self do
        {
          # TODO: backend_pid: connection.backend_pid,
        }
      end
    end

    private

    def parse_payload(payload)
      Que.deserialize_json(payload)
    rescue JSON::ParserError
      nil # TODO: Maybe log? Or notify the error?
    end

    def message_matches_format?(message, format)
      return false unless message.length == format.length

      format.all? do |key, type|
        value = message.fetch(key) { return false }
        Que.assert?(type, value)
      end
    end
  end
end
