# frozen_string_literal: true

# Various pieces of metadata about a job, including its sort key, whether it's
# currently locked, and the full job data if we have it.

module Que
  class Metajob
    attr_reader :sort_key

    def initialize(sort_key:, is_locked:, source:)
      @sort_key  = sort_key
      @is_locked = is_locked
      @source    = source
    end

    def id
      sort_key.fetch(:id)
    end
  end
end
