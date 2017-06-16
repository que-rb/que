# frozen_string_literal: true

module Que
  class Listener
    def initialize(pool:)
      @pool = pool
    end

    def unlisten
      @pool.checkout do |conn|
        # Unlisten and drain notifications before releasing the connection.
        @pool.execute "UNLISTEN *"
        {} while conn.notifies
      end
    end
  end
end
