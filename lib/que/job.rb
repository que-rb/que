module Que
  class Job < Sequel::Model
    # The Job priority scale:
    #   1 = Urgent. Somebody's staring at a spinner waiting on this.
    #   2 = ASAP. Should happen within a few minutes of the run_at time.
    #   3 = Time-sensitive. Sooner is better than later.
    #   4 = Time-insensitive. Shouldn't get delayed forever, though.
    #   5 = Whenever. Timing doesn't matter. May be a huge backlog of these.

    unrestrict_primary_key

    plugin :single_table_inheritance, :type, :key_map   => proc(&:to_s),
                                             :model_map => proc(&:constantize)

    class Retry < StandardError; end

    class << self
      # Default is lowest priority, meaning jobs can be done whenever.
      def default_priority
        @default_priority ||= 5
      end

      def queue(*args)
        create values_for_args *args
      end

      def queue_array(array, options = {})
        # Since this is a direct insert, we have to special-case the callbacks.
        options[:priority] ||= default_priority

        multi_insert array.map { |element|
          args = Array.wrap(element)
          args << args.extract_options!.merge(options)
          values_for_args(*args).tap do |values|
            values[:type] = to_s
            values[:args] = values[:args].to_json
          end
        }

        if array.any? && !options[:run_at]
          case Worker.state
            when :sync  then DB.after_commit { {} while Job.work }
            when :async then DB.after_commit { Worker.wake!      }
          end
        end
      end

      def values_for_args(*args)
        args.extract_options!.tap do |attrs|
          attrs[:args] = args << attrs.slice!(:run_at, :priority)
        end
      end

      def work(options = {})
        # Since we're taking session-level advisory locks, we have to hold the
        # same connection throughout the process of getting a job, working it,
        # deleting it, and removing the lock.

        DB.synchronize do
          begin
            return unless job = LOCK.call(:priority => options[:priority] || 5)

            # Edge case: It's possible for the lock statement to have grabbed a
            # job that's already been worked, if the statement took its MVCC
            # snapshot while the job was processing (making it appear to still
            # exist), but didn't actually attempt to lock it until the job was
            # finished (making it appear to be unlocked). Now that we have the
            # job lock, we know that a previous worker would have deleted it by
            # now, so we just make sure it still exists before working it.
            this = dataset.where(:priority => job[:priority], :run_at => job[:run_at], :job_id => job[:job_id])
            return if this.empty?

            # Split up model instantiation from the DB query, so that model
            # instantiation errors can be caught.
            model = sti_load(job)

            # Track how long different jobs take to process.
            ms = time_ms{model.work}.round(1)
            Que.logger.info "Worked job in #{ms} ms: #{model.inspect}"

            # Most jobs destroy themselves transactionally in #work. If not,
            # take care of them. Jobs that don't destroy themselves run the risk
            # of being repeated after a crash.
            model.destroy if model.persisted?

            # Make sure to return the finished job.
            model
          rescue Retry
            # Don't destroy the job or mark it as having errored. It can be
            # retried as soon as it is unlocked.
          rescue => error
            if job && job[:data]
              count = (job[:data][:error_count] || 0) + 1

              this.update :run_at => (count ** 4 + 3).seconds.from_now,
                          :data   => {:error_count => count, :error_message => error.message, :error_backtrace => error.backtrace.join("\n")}.pg_json
            end

            raise
          ensure
            DB.get{pg_advisory_unlock(job[:job_id])} if job
          end
        end
      end
    end

    # Send the args attribute to the perform() method.
    def work
      perform(*args)
    end

    # Call perform on a job to run it. No perform method means NOOP.
    def perform(*args)
    end

    private

    # If we add any more callbacks here, make sure to also special-case them in
    # queue_array above.
    def before_create
      self.priority ||= self.class.default_priority

      # If there's no run_at set, the job needs to be run immediately, so we
      # need to trigger a worker to work it after it's committed and visible.
      if run_at.nil?
        case Worker.state
          when :sync  then DB.after_commit { Job.work     }
          when :async then DB.after_commit { Worker.wake! }
        end
      end

      super
    end

    LOCK = DB.query {
      with_recursive :cte,
        DB.query {
          select { [job.pg_row.*, pg_try_advisory_lock(job.pg_row[:job_id]).as(:locked)] }
          from DB.query {
            select :job
            from :jobs => :job
            where { run_at <= now{} }
            where { priority <= :$priority }
            order_by :priority, :run_at, :job_id
            limit 1
          }
        },
        DB.query {
          select { [job.pg_row.*, pg_try_advisory_lock(job.pg_row[:job_id]).as(:locked)] }
          from DB.query {
            select DB.query {
              select :job
              from :jobs => :job
              where { run_at <= now{} }
              where { priority <= :$priority }
              where { self.> [:priority, :run_at, :job_id], [:cte__priority, :cte__run_at, :cte__job_id] }
              order_by :priority, :run_at, :job_id
              limit 1
            } => :job
            from :cte
            exclude :cte__locked
            limit 1
          }
        }
      from :cte
      where :locked
    }.prepare :first, :lock_job

    # This query was slightly adapted from one by RhodiumToad in #postgresql:

    # with recursive
    #  t as (select (j).*, pg_try_advisory_lock((j).job_id) as locked
    #          from (select j from jobs j
    #                 where run_at >= now()
    #                 order by priority, run_at, job_id limit 1) s
    #        union all
    #        select (j).*, pg_try_advisory_lock((j).job_id)
    #          from (select (select j from jobs j
    #                         where run_at >= now()
    #                           and (priority,run_at,job_id) > (t.priority,t.run_at,t.job_id)
    #                         order by priority, run_at, job_id limit 1) as j
    #                  from t
    #                 where not t.locked limit 1) s)
    # select * from t where locked;
    # -- for best results create an index on jobs (priority,run_at,job_id) but unlike other approaches,
    # -- this one is guaranteed not to lock more than one row even if the index is absent or unused



    # An alternate scheme using LATERAL, which will arrive in Postgres 9.3.
    # Basically the same, but benchmark to see if it's faster/just as reliable.

    # with recursive
    #  t as (select *, pg_try_advisory_lock(s.job_id) as locked
    #          from (select * from jobs j
    #                 where run_at >= now()
    #                 order by priority, run_at, job_id limit 1) s
    #        union all
    #        select j.*, pg_try_advisory_lock(j.job_id)
    #          from (select * from t where not locked) t,
    #               lateral (select * from jobs
    #                         where run_at >= now()
    #                           and (priority,run_at,job_id) > (t.priority,t.run_at,t.job_id)
    #                         order by priority, run_at, job_id limit 1) j
    # select * from t where locked;
  end
end
