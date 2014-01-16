# Don't run these specs in JRuby until jruby-pg is compatible with ActiveRecord.
unless defined?(RUBY_ENGINE) && RUBY_ENGINE == 'jruby'

  require 'spec_helper'
  require 'active_record'

  ActiveRecord::Base.establish_connection(QUE_URL)
  Que.connection = ActiveRecord
  QUE_ADAPTERS[:active_record] = Que.adapter

  describe "Que using the ActiveRecord adapter" do
    before { Que.adapter = QUE_ADAPTERS[:active_record] }

    it_behaves_like "a Que adapter"

    it "should use the same connection that ActiveRecord does" do
      begin
        class ActiveRecordJob < Que::Job
          def run
            $pid1 = Integer(Que.execute("select pg_backend_pid()").first['pg_backend_pid'])
            $pid2 = Integer(ActiveRecord::Base.connection.select_value("select pg_backend_pid()"))
          end
        end

        ActiveRecordJob.queue
        Que::Job.work

        $pid1.should == $pid2
      ensure
        $pid1 = $pid2 = nil
      end
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

    it "should be able to tell when it's in an ActiveRecord transaction" do
      Que.adapter.should_not be_in_transaction
      ActiveRecord::Base.transaction do
        Que.adapter.should be_in_transaction
      end
    end
  end
end
