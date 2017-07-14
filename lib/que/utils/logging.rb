# frozen_string_literal: true

# Tools for logging from Que.

module Que
  module Utils
    module Logging
      def log(level: :info, event:, **data)
        data =
          {
            lib:      :que,
            hostname: CURRENT_HOSTNAME,
            pid:      Process.pid,
            thread:   Thread.current.object_id,
            event:    Que.assert(Symbol, event),
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
      def internal_log(event)
        if l = internal_logger
          data = {}
          data[:internal_event] = Que.assert(Symbol, event)
          data.merge!(Que.assert(Hash, yield))
          l.info(JSON.dump(data))
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
