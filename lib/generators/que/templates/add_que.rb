# frozen_string_literal: true

class AddQue < ActiveRecord::Migration[4.2]
  def self.up
    # The current version as of this migration's creation.
    Que.migrate! :version => 3
  end

  def self.down
    # Completely removes Que's job queue.
    Que.migrate! :version => 0
  end
end
