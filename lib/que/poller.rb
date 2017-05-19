# frozen_string_literal: true

module Que
  class Poller
    attr_reader \
      :pool,
      :queue,
      :poll_interval,
      :last_polled_at,
      :last_poll_satisfied

    def initialize(
      pool:,
      queue:,
      poll_interval:
    )
      @pool                = pool
      @queue               = queue
      @poll_interval       = poll_interval
      @last_polled_at      = nil
      @last_poll_satisfied = nil
    end

    def poll(limit, held_locks:)
      return unless should_poll?

      jobs =
        pool.execute(
          :poll_jobs,
          [
            @queue,
            "{#{held_locks.to_a.join(',')}}",
            limit,
          ]
        )

      @last_polled_at      = Time.now
      @last_poll_satisfied = limit == jobs.count

      Que.log(
        level: :debug,
        event: :locker_polled,
        limit: limit,
        locked: jobs.count,
      )

      jobs
    end

    def should_poll?
      # Never polled before?
      last_poll_satisfied.nil? ||
      # Plenty of jobs were available last time?
      last_poll_satisfied == true ||
      poll_interval_elapsed?
    end

    def poll_interval_elapsed?
      return unless interval = poll_interval
      (Time.now - last_polled_at) > interval
    end
  end
end
