# Don't run these specs in JRuby until jruby-pg is compatible with ActiveRecord.
unless defined?(RUBY_ENGINE) && RUBY_ENGINE == 'jruby'

  require 'spec_helper'
  require 'active_record'

  ActiveRecord::Base.establish_connection(QUE_URL)
  Que.connection = ActiveRecord
  QUE_ADAPTERS[:active_record] = Que.adapter

  describe "Que using the ActiveRecord adapter" do
    before { Que.adapter = QUE_ADAPTERS[:active_record] }

    it_behaves_like "a multi-threaded Que adapter"

    it "should use the same connection that ActiveRecord does" do
      class ActiveRecordJob < Que::Job
        def run
          $pid1 = Que.execute("SELECT pg_backend_pid()").first['pg_backend_pid'].to_i
          $pid2 = ActiveRecord::Base.connection.select_all("select pg_backend_pid()").rows.first.first.to_i
        end
      end

      ActiveRecordJob.queue
      Que::Job.work

      $pid1.should == $pid2
    end

    it "should instantiate args as ActiveSupport::HashWithIndifferentAccess" do
      ArgsJob.queue :param => 2
      Que::Job.work
      $passed_args.first[:param].should == 2
      $passed_args.first.should be_an_instance_of ActiveSupport::HashWithIndifferentAccess
    end

    it "should support Rails' special extensions for times" do
      Que.mode = :async
      sleep_until { Que::Worker.workers.all? &:sleeping? }

      Que::Job.queue :run_at => 1.minute.ago
      DB[:que_jobs].get(:run_at).should be_within(3).of Time.now - 60

      Que.wake_interval = 0.005.seconds
      sleep_until { DB[:que_jobs].empty? }
    end

    it "should wake up a Worker after queueing a job in async mode, waiting for a transaction to commit if necessary" do
      Que.mode = :async
      sleep_until { Que::Worker.workers.all? &:sleeping? }

      # Wakes a worker immediately when not in a transaction.
      Que::Job.queue
      sleep_until { Que::Worker.workers.all?(&:sleeping?) && DB[:que_jobs].empty? }

      ActiveRecord::Base.transaction do
        Que::Job.queue
        Que::Worker.workers.each { |worker| worker.should be_sleeping }
      end
      sleep_until { Que::Worker.workers.all?(&:sleeping?) && DB[:que_jobs].empty? }

      # Do nothing when queueing with a specific :run_at.
      BlockJob.queue :run_at => Time.now
      Que::Worker.workers.each { |worker| worker.should be_sleeping }
    end
  end
end
