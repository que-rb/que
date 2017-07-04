# frozen_string_literal: true

# Tools for logging from Que.

module Que
  module Utils
    module Logging
      def log(level: :info, **data)
        data =
          {
            lib:      :que,
            hostname: CURRENT_HOSTNAME,
            pid:      Process.pid,
            thread:   Thread.current.object_id
          }.merge(data)

        if l = logger
          begin
            if output = log_formatter.call(data)
              l.send level, output
            end
          rescue => e
            msg =
              "Error raised from Que.log_formatter proc:" +
              " #{e.class}: #{e.message}\n#{e.backtrace}"

            l.error(msg)
          end
        end
      end

      attr_writer :logger, :log_formatter

      def logger
        @logger.respond_to?(:call) ? @logger.call : @logger
      end

      def log_formatter
        @log_formatter ||= JSON.method(:dump)
      end
    end
  end
end
