# frozen_string_literal: true

# This task is used to test Que's behavior when its process is shut down.

# The situation we're trying to avoid occurs when the process dies while a job
# is in the middle of a transaction - ideally, the transaction would be rolled
# back and the job could just be reattempted later, but if we're not careful,
# the transaction could be committed prematurely. For specifics, see here:

# http://coderrr.wordpress.com/2011/05/03/beware-of-threadkill-or-your-activerecord-transactions-are-in-danger-of-being-partially-committed/

# So, this task opens a transaction within a job, makes a write, then prompts
# you to kill it with one of a few signals. You can then run it again to make
# sure that the write was rolled back (if it wasn't, Que isn't functioning
# like it should). This task only explicitly tests Sequel, but the behavior
# for ActiveRecord is very similar.

task :safe_shutdown do
  require 'sequel'
  require 'que'

  url = ENV['DATABASE_URL'] || 'postgres://postgres:@localhost/que-test'
  DB = Sequel.connect(url)

  if DB.table_exists?(:que_jobs)
    if DB[:que_jobs].where(id: 0).count > 0
      puts "Uh-oh! Previous shutdown wasn't clean!"
    end
    DB.drop_table :que_jobs
  end

  Que.connection_proc = DB.method(:synchronize)
  Que.create!

  $queue = Queue.new

  class SafeJob < Que::Job
    def run
      DB.transaction do
        DB[:que_jobs].insert(id: 0, job_class: 'Que::Job')
        $queue.push nil
        sleep
      end
    end
  end

  SafeJob.enqueue
  Que.mode = :async
  $queue.pop

  puts "From a different terminal window, run one of the following:"
  %w(SIGINT SIGTERM SIGKILL).each do |signal|
    puts "kill -#{signal} #{Process.pid}"
  end

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
