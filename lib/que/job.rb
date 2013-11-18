require 'json'

module Que
  class Job
    def initialize(attrs)
      @attrs = attrs
    end

    # Subclasses should define their own run methods, but keep an empty one
    # here so we can just do Que::Job.queue in testing.
    def run(*args)
    end

    def _run
      start = Time.now

      run *@attrs[:args]
      destroy unless @destroyed

      Que.log :info, "Worked job in #{((Time.now - start) * 1000).round(1)} ms: #{inspect}"
    end

    private

    def destroy
      Que.execute :destroy_job, [@attrs[:priority], @attrs[:run_at], @attrs[:job_id]]
      @destroyed = true
    end

    class << self
      def queue(*args)
        if args.last.is_a?(Hash)
          options  = args.pop
          run_at   = options.delete(:run_at)
          priority = options.delete(:priority)
          args << options if options.any?
        end

        attrs = {:job_class => to_s, :args => JSON.dump(args)}

        if t = run_at || @default_run_at && @default_run_at.call
          attrs[:run_at] = t
        end

        if p = priority || @default_priority
          attrs[:priority] = p
        end

        if Que.mode == :sync
          run_job(attrs)
        else
          Que.execute *insert_sql(attrs)
        end
      end

      def work
        # Job.work will typically be called in a loop, where we'd sleep when
        # there's no more work to be done, so its return value should reflect
        # whether we should hit the database again or not. So, return truthy
        # if we worked a job or encountered a typical error while working a
        # job, and falsy if we found nothing to do or hit a connection error.

        # Since we're taking session-level advisory locks, we have to hold the
        # same connection throughout the process of getting a job, working it,
        # deleting it, and removing the lock.
        Que.adapter.checkout do
          begin
            if row = Que.execute(:lock_job).first
              # Edge case: It's possible to have grabbed a job that's already
              # been worked, if the SELECT took its MVCC snapshot while the
              # job was processing, but didn't attempt the advisory lock until
              # it was finished. Now that we have the job lock, we know that a
              # previous worker would have deleted it by now, so we just
              # double check that it still exists before working it.

              # Note that there is currently no spec for this behavior, since
              # I'm not sure how to reliably commit a transaction that deletes
              # the job in a separate thread between this lock and check.
              return true if Que.execute(:check_job, [row['priority'], row['run_at'], row['job_id']]).none?

              run_job(row)
            end
          rescue => error
            begin
              if row
                # Borrowed the exponential backoff formula and error data format from delayed_job.
                count   = row['error_count'].to_i + 1
                run_at  = Time.now + (count ** 4 + 3)
                message = "#{error.message}\n#{error.backtrace.join("\n")}"
                Que.execute :set_error, [count, run_at, message, row['priority'], row['run_at'], row['job_id']]
              end
            rescue
              # If we can't reach the DB for some reason, too bad, but don't
              # let it crash the work loop.
            end

            if Que.error_handler
              Que.error_handler.call(error) rescue nil
            end

            # If it's a garden variety error, we can just return true, pick up
            # another job, no big deal. If it's a PG::Error, though, assume
            # it's a disconnection or something and that we shouldn't just hit
            # the database again right away.
            return !error.is_a?(PG::Error)
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

      def run_job(attrs)
        attrs = indifferentiate(attrs)
        attrs[:args] = indifferentiate(JSON.load(attrs[:args]))
        const_get(attrs[:job_class]).new(attrs).tap(&:_run)
      end

      def indifferentiate(input)
        case input
        when Hash
          h = indifferent_hash
          input.each { |k, v| h[k] = indifferentiate(v) }
          h
        when Array
          input.map { |v| indifferentiate(v) }
        else
          input
        end
      end

      def indifferent_hash
        # Tiny hack to better support Rails.
        if {}.respond_to?(:with_indifferent_access)
          {}.with_indifferent_access
        else
          Hash.new { |hash, key| hash[key.to_s] if Symbol === key }
        end
      end
    end
  end
end
