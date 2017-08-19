# frozen_string_literal: true

# Various pieces of metadata about a job, including its sort key, whether it's
# currently locked, and the full job data if we have it.

module Que
  class Metajob
    attr_reader :sort_key
    attr_accessor :is_locked

    SORT_KEYS = [:priority, :run_at, :id].freeze

    def initialize(sort_key:, is_locked:, source:)
      @sort_key  = sort_key
      @is_locked = is_locked
      @source    = source
    end

    def id
      sort_key.fetch(:id)
    end

    def <=>(other)
      k1 = sort_key
      k2 = other.sort_key

      SORT_KEYS.each do |key|
        value1 = k1.fetch(key)
        value2 = k2.fetch(key)

        return -1 if value1 < value2
        return  1 if value1 > value2
      end

      0
    end

    def priority_sufficient?(priority)
      priority.nil? || sort_key.fetch(:priority) <= priority
    end
  end
end
