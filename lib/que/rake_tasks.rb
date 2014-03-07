namespace :que do
  desc "Process Que's jobs using a forking worker"
  task :fork_and_work => :environment do
    require 'logger'
    Que.logger = Logger.new(STDOUT)
    Que.logger.level  = Logger.const_get((ENV['QUE_LOG_LEVEL'] || 'INFO').upcase)
    # When we support multiple workers?
    Que.worker_count  = (ENV['QUE_WORKER_COUNT'] || 1).to_i

    # Preload MultiJson's code for finding the most efficient json loader
    # so we don't need to do this inside each worker process.
    if defined?(MultiJson)
      MultiJson.load('[]')
    end

    worker_pid = nil
    stop = false

    trap('INT') do
      $stderr.puts "Asking worker process to stop..."
      stop = true
      Process.kill('INT', worker_pid) if worker_pid
    end

    loop do
      break if stop
      worker_pid = fork do
        Que.after_fork
        stop = false
        trap('INT') {stop = true}

        loop do
          break if stop
          result = Que::Job.work
          if result && result[:event] == :job_unavailable
            # No jobs worked, check again in a bit.
            sleep 0.1
          else
            # job worked, fork new worker process
            Que.logger.info "job status: #{ result[:event] }"
            break
          end
        end
      end
      Process.wait(worker_pid)
    end
  end

  desc "Process Que's jobs using a worker pool"
  task :work => :environment do
    require 'logger'

    Que.logger        = Logger.new(STDOUT)
    Que.logger.level  = Logger.const_get((ENV['QUE_LOG_LEVEL'] || 'INFO').upcase)
    Que.worker_count  = (ENV['QUE_WORKER_COUNT'] || 4).to_i
    Que.wake_interval = (ENV['QUE_WAKE_INTERVAL'] || 0.1).to_f

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
