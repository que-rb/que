namespace :que do
  desc "Migrate Que's job table to the most recent version (creating it if it doesn't exist)"
  task :migrate => :environment do
    Que.migrate!
  end

  desc "Drop Que's job table"
  task :drop => :environment do
    Que.drop!
  end

  desc "Clear Que's job table"
  task :clear => :environment do
    Que.clear!
  end
end
