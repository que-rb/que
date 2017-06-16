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
      # TODO: Return messages in bulk.

      @pool.checkout do |conn|
        conn.wait_for_notify(timeout) do |_, _, payload|
          message =
            begin
              Que.deserialize_json(payload)
            rescue JSON::ParserError
              nil
            end

          message_type = message && message.delete(:message_type)
          return unless message_type == 'new_job'

          Que.log(
            level: :debug,
            event: :job_notified,
            job:   message,
          )

          message[:run_at] = Time.parse(message.fetch(:run_at))

          return {new_job: [message]}
        end
      end
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
