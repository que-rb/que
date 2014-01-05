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
      Que::Job.queue :run_at => 1.minute.from_now
      DB[:que_jobs].get(:run_at).should be_within(3).of Time.now + 60
    end
  end
end
