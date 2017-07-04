# frozen_string_literal: true

# An assertion helper, so that error reports will hopefully be of higher
# quality.

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
