# frozen_string_literal: true

module Que
  class Listener
    MESSAGE_FORMATS = {}

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

    def wait_for_grouped_messages(timeout)
      messages = wait_for_messages(timeout)

      output = {}

      messages.each do |message|
        message_type = message.delete(:message_type)

        (output[message_type.to_sym] ||= []) << message.freeze
      end

      output
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

      accumulated_messages = []

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
            next unless message = parse_payload(payload)

            case message
            when Array then accumulated_messages.concat(message)
            when Hash  then accumulated_messages << message
            else raise Error, "Unexpected parse_payload output: #{message.class}"
            end
          end

        break unless notification_received
      end

      return accumulated_messages if accumulated_messages.empty?

      Que.internal_log(:listener_received_messages, self) do
        {
          backend_pid: connection.backend_pid,
          channel:     channel,
          messages:    accumulated_messages,
        }
      end

      accumulated_messages.keep_if do |message|
        next unless message.is_a?(Hash)
        next unless type = message[:message_type]
        next unless type.is_a?(String)
        next unless format = MESSAGE_FORMATS[type.to_sym]

        if message_matches_format?(message, format)
          true
        else
          error_message = [
            "Message of type '#{type}' doesn't match format!",
            # Massage message and format a bit to make these errors more readable.
            "Message: #{Hash[message.reject{|k,v| k == :message_type}.sort_by{|k,v| k}].inspect}",
            "Format: #{Hash[format.sort_by{|k,v| k}].inspect}",
          ].join("\n")

          Que.notify_error_async(Error.new(error_message))
          false
        end
      end

      Que.internal_log(:listener_filtered_messages, self) do
        {
          backend_pid: connection.backend_pid,
          channel:     channel,
          messages:    accumulated_messages,
        }
      end

      accumulated_messages
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
    rescue JSON::ParserError => e
      Que.notify_error_async(e)
      nil
    end

    def message_matches_format?(message, format)
      # Add one to account for message_type key, which we've confirmed exists.
      return false unless message.length == format.length + 1

      format.all? do |key, type|
        value = message.fetch(key) { return false }
        Que.assert?(type, value)
      end
    end
  end
end
