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

        attrs = {:type => to_s, :args => JSON.dump(args)}

        if t = run_at || @default_run_at && @default_run_at.call
          attrs[:run_at] = t
        end

        if p = priority || @default_priority
          attrs[:priority] = p
        end

        Que.execute *insert_sql(attrs)
      end

      def work
        # Job.work will typically be called in a loop, where we'd sleep when
        # there's no more work to be done, so its return value should reflect
        # whether there is likely to be work available. So, return truthy if
        # we worked a job or encountered an error while working a job, and
        # falsy if we found nothing to do.

        # Since we're taking session-level advisory locks, we have to hold the
        # same connection throughout the process of getting a job, working it,
        # deleting it, and removing the lock.
        Que.adapter.checkout do
          begin
            if row = Que.execute(:lock_job).first
              # Edge case: It's possible for the lock statement to have
              # grabbed a job that's already been worked, if the statement
              # took its MVCC snapshot while the job was processing, but
              # didn't attempt the advisory lock until it was finished. Now
              # that we have the job lock, we know that a previous worker
              # would have deleted it by now, so we just double check that it
              # still exists before working it.

              # Note that there is currently no spec for this behavior, since
              # I'm not sure how to deterministically commit a transaction
              # that deletes a job in a separate thread between the lock and
              # check queries.
              return true if Que.execute(:check_job, [row['priority'], row['run_at'], row['job_id']]).none?

              # Actually work the job, log it, and return it.
              job = const_get(row['type']).new(row)
              start = Time.now
              job._run
              time = Time.now - start
              Que.log :info, "Worked job in #{(time * 1000).round(1)} ms: #{job.inspect}"
              job
            end
          rescue => error
            if row
              # Borrowed the exponential backoff formula and error data format from delayed_job.
              count   = row['error_count'].to_i + 1
              run_at  = Time.now + (count ** 4 + 3)
              message = "#{error.message}\n#{error.backtrace.join("\n")}"
              Que.execute :set_error, [count, run_at, message, row['priority'], row['run_at'], row['job_id']]
            end

            if Que.error_handler
              Que.error_handler.call(error) rescue nil
            end

            return true
          ensure
            # Clear the advisory lock we took when locking the job. Important
            # to do this so that they don't pile up in the database.
            Que.execute "SELECT pg_advisory_unlock($1)", [row['job_id']] if row
          end
        end
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

        ["INSERT INTO que_jobs (#{columns.join(', ')}) VALUES (#{placeholders.join(', ')})", values]
      end
    end

    def initialize(attrs)
      @attrs = attrs
    end

    def _run
      run *_indifferentiate(JSON.load(@attrs['args']))
      destroy unless @destroyed
    end

    # A job without a run method defined doesn't do anything. This is useful in testing.
    def run(*args)
    end

    private

    def destroy
      Que.execute :destroy_job, [@attrs['priority'], @attrs['run_at'], @attrs['job_id']]
      @destroyed = true
    end

    def _indifferentiate(input)
      case input
      when Hash
        h = _indifferent_hash
        input.each { |k, v| h[k] = _indifferentiate(v) }
        h
      when Array
        input.map { |v| _indifferentiate(v) }
      else
        input
      end
    end

    def _indifferent_hash
      # Tiny hack to better support Rails.
      if {}.respond_to?(:with_indifferent_access)
        {}.with_indifferent_access
      else
        Hash.new { |hash, key| hash[key.to_s] if Symbol === key }
      end
    end
  end
end
