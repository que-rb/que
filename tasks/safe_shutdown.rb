# This task is used to test Que's behavior when its process is shut down.

# The situation we're trying to avoid occurs when the process dies while a job
# is in the middle of a transaction - ideally, the transaction would be rolled
# back and the job could just be reattempted later, but if we're not careful,
# the transaction could be committed too early. For specifics, see this post:

# http://coderrr.wordpress.com/2011/05/03/beware-of-threadkill-or-your-activerecord-transactions-are-in-danger-of-being-partially-committed/

# So, this task opens a transaction within a job, makes a write, then prompts
# you to kill it with one of a few signals. It also checks to see whether the
# previous shutdown was clean or not.

task :safe_shutdown do
  require 'sequel'
  require 'que'

  url = ENV['DATABASE_URL'] || 'postgres://postgres:@localhost/que-test'
  DB = Sequel.connect(url)

  if DB.table_exists?(:que_jobs)
    puts "Uh-oh! Previous shutdown wasn't clean!" if DB[:que_jobs].where(:job_id => 0).count > 0
    DB.drop_table :que_jobs
  end

  Que.connection = DB
  Que.create!

  $queue = Queue.new

  class SafeJob < Que::Job
    def run
      DB.transaction do
        DB[:que_jobs].insert(:job_id => 0, :job_class => 'Que::Job')
        $queue.push nil
        sleep
      end
    end
  end

  SafeJob.queue
  Que.mode = :async
  $queue.pop

  puts "From a different terminal window, run one of the following:"
  %w(SIGINT SIGTERM SIGKILL).each do |signal|
    puts "kill -#{signal} #{Process.pid}"
  end

  # Put signal trappers to test the behavior of here:
  stop = false

  %w(INT TERM).each do |signal|
    trap signal do
      puts "SIG#{signal} caught, finishing current jobs and shutting down..."
      Que.mode = :off
      stop = true
    end
  end

  loop do
    sleep 0.01
    break if stop
  end
end
