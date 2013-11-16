namespace :que do
  desc "Creates Que's job table"
  task :create => :environment do
    Que.create!
  end

  desc "Drops Que's job table"
  task :drop => :environment do
    Que.drop!
  end

  desc "Clears Que's job table"
  task :clear => :environment do
    Que.clear!
  end
end
