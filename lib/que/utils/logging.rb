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

        if l = get_logger
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

      # Logging method used specifically to instrument Que's internals. Fetches
      # log contents by yielding to a block so that we avoid allocating
      # unnecessary objects in production use.
      def internal_log
        if l = internal_logger
          data = yield

          output =
            case data
            when Hash   then JSON.dump(data)
            when String then data
            else             data.to_s
            end

          l.info(output)
        end
      end

      attr_accessor :logger, :log_formatter, :internal_logger

      def get_logger
        @logger.respond_to?(:call) ? @logger.call : @logger
      end

      def log_formatter
        @log_formatter ||= JSON.method(:dump)
      end
    end
  end
end
