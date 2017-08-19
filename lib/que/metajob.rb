# frozen_string_literal: true

# Various pieces of metadata about a job, including its sort key, whether it's
# currently locked, and the full job data if we have it.

module Que
  class Metajob
    attr_reader :sort_key
    attr_accessor :job

    SORT_KEYS = [:priority, :run_at, :id].freeze

    def initialize(sort_key:, source:, job: nil)
      @sort_key  = sort_key
      @source    = source
      @job       = job
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
