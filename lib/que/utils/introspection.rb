# frozen_string_literal: true

# Tools for introspecting the state of the job queue.

module Que
  module Utils
    module Introspection
      def job_stats
        execute :job_stats
      end

      def job_states
        execute :job_states
      end
    end
  end
end
