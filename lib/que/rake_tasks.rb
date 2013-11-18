require 'logger'

namespace :que do
  desc "Process Que's jobs using a worker pool"
  task :work => :environment do
    Que.logger       = Logger.new(STDOUT)
    Que.mode         = :async
    Que.worker_count = (ENV['WORKER_COUNT'] || 4).to_i

    trap('INT') { exit }
    trap 'TERM' do
      puts "SIGTERM, finishing current jobs and shutting down..."
      Que.mode = :off
    end

    sleep
  end

  desc "Process Que's jobs in a single thread"
  task :work_single => :environment do
    Que.logger = Logger.new(STDOUT)
    sleep_period = (ENV['SLEEP_PERIOD'] || 5).to_i
    loop { sleep(sleep_period) unless Que::Job.work }
  end

  desc "Create Que's job table"
  task :create => :environment do
    Que.create!
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
