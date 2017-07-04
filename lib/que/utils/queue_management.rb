# frozen_string_literal: true

module Que
  module Utils
    module QueueManagement
      # Have to support create! and drop! for old migrations. They just created
      # and dropped the bare table.
      def create!
        migrate!(version: 1)
      end

      def drop!
        migrate!(version: 0)
      end

      def clear!
        execute "DELETE FROM que_jobs"
      end
    end
  end
end
