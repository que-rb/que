require 'json'

module Que
  class Job
    class << self
      def queue(*args)
        if args.last.is_a?(Hash)
          options  = args.pop
          run_at   = options.delete(:run_at)
          priority = options.delete(:priority)
          args << options if options.any?
        end

        attrs = {
          :type => to_s,
          :args => JSON.dump(args)
        }

        if t = run_at || @default_run_at && @default_run_at.call
          attrs[:run_at] = t
        end

        if p = priority || @default_priority
          attrs[:priority] = p
        end

        Que.execute *insert_sql(attrs)
      end

      def work
        if row = Que.execute(LockSQL).first
          job = const_get(row['type']).new
          job.run(*JSON.load(row['args']))
          Que.execute "DELETE FROM que_jobs WHERE priority = $1 AND run_at = $2 AND job_id = $3", [row['priority'], row['run_at'], row['job_id']]
          job
        end
      ensure
        Que.execute "SELECT pg_advisory_unlock($1)", [row['job_id']] if row
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
