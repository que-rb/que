# frozen_string_literal: true

module Que
  class Listener
    MESSAGE_CALLBACKS = Utils::Registrar.new(raise_on_missing: false)
    MESSAGE_FORMATS   = Utils::Registrar.new(raise_on_missing: false, &:freeze)

    attr_reader :connection, :channel

    def initialize(connection:, channel: nil)
      @connection = connection
      @channel    = channel || "que_listener_#{connection.backend_pid}"

      Que.internal_log :listener_instantiate, self do
        {
          backend_pid: connection.backend_pid,
        }
      end
    end

    def listen
      connection.execute "LISTEN #{channel}"
    end

    def wait_for_messages(timeout)
      # Make sure we never pass nil to this method, so we don't hang the thread.
      Que.assert(Numeric, timeout)

      Que.internal_log :listener_waiting, self do
        {
          backend_pid: connection.backend_pid,
          channel:     channel,
          timeout:     timeout,
        }
      end

      output = {}

      # Notifications often come in batches (especially when a transaction that
      # inserted many jobs commits), so we want to loop and pick up all the
      # received notifications before continuing.
      loop do
        notification_received =
          connection.wait_for_notify(timeout) do |channel, pid, payload|
            # We've received a notification, so zero out the timeout before we
            # loop again to check for another message. This ensures that we
            # don't wait an additional `timeout` seconds after processing the
            # final message before this method returns.
            timeout = 0

            Que.internal_log(:listener_received_notification, self) do
              {
                channel:     channel,
                backend_pid: connection.backend_pid,
                source_pid:  pid,
                payload:     payload,
              }
            end

            # Be very defensive about the message we receive - it may not be
            # valid JSON or have the structure we expect.
            next unless messages = parse_payload(payload)

            messages = [messages] unless messages.is_a?(Array)

            messages.each do |message|
              message_type = message && message.delete(:message_type)
              next unless message_type.is_a?(String)

              (output[message_type.to_sym] ||= []) << message
            end
          end

        break unless notification_received
      end

      return output if output.empty?

      Que.internal_log(:listener_received_messages, self) do
        {
          backend_pid: connection.backend_pid,
          channel:     channel,
          messages:    output,
        }
      end

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

      Que.internal_log(:listener_processed_messages, self) do
        {
          backend_pid: connection.backend_pid,
          channel:     channel,
          messages:    output,
        }
      end

      output
    end

    def unlisten
      # Be sure to drain all notifications so that any code that uses this
      # connection later doesn't receive any nasty surprises.
      connection.execute "UNLISTEN *"
      connection.drain_notifications

      Que.internal_log :listener_unlisten, self do
        {
          backend_pid: connection.backend_pid,
          channel:     channel,
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
