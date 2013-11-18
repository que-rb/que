class AddQue < ActiveRecord::Migration
  def self.up
    Que.create!
  end

  def self.down
    Que.drop!
  end
end
