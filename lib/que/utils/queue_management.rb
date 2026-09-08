# frozen_string_literal: true

# Tools for managing the contents/state of the queue.

module Que
  module Utils
    module QueueManagement
      def clear!
        execute "DELETE FROM que_jobs"
      end

      # Very old migrations may use Que.create! and Que.drop!, which just
      # created and dropped the initial version of the jobs table.
      def create!; migrate!(version: 1); end
      def drop!; migrate!(version: 0); end
    end
  end
end
