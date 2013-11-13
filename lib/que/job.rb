require 'json'

module Que
  class Job
    class << self
      def queue(*args)
        if args.last.is_a?(Hash)
          options  = args.pop
          run_at   = options.delete(:run_at)
          priority = options.delete(:priority)
          args << options
        end

        attrs = {
          :type => to_s,
          :args => JSON.dump(args)
        }

        attrs[:run_at]   = run_at   if run_at
        attrs[:priority] = priority if priority

        Que.execute *insert_sql(attrs)
      end

      private

      # Column names are not escaped, so this method should not be called with untrusted hashes.
      def insert_sql(hash)
        number       = 0
        columns      = []
        placeholders = []
        values       = []

        hash.each do |key, value|
          columns      << key
          placeholders << "$#{number += 1}"
          values       << value
        end

        ["INSERT INTO que_jobs (#{columns.join(', ')}) VALUES (#{placeholders.join(', ')});", values]
      end
    end
  end
end
