namespace :que do
  desc "Process Que's jobs using a worker pool"
  task :work => :environment do
    require 'logger'

    Que.logger        = Logger.new(STDOUT)
    Que.worker_count  = (ENV['QUE_WORKER_COUNT'] || 4).to_i
    Que.wake_interval = (ENV['QUE_WAKE_INTERVAL'] || 0.5).to_f

    # When changing how signals are caught, be sure to test the behavior with
    # the rake task in tasks/safe_shutdown.rb.

    stop = false
    trap('INT'){stop = true}

    at_exit do
      $stdout.puts "Finishing Que's current jobs before exiting..."
      Que.mode = :off
      $stdout.puts "Que's jobs finished, exiting..."
    end

    loop do
      sleep 0.01
      break if stop
    end
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
