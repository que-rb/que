# Don't run these specs in JRuby until jruby-pg is compatible with ActiveRecord.
unless defined?(RUBY_ENGINE) && RUBY_ENGINE == 'jruby'

  require 'spec_helper'
  require 'active_record'

  ActiveRecord::Base.establish_connection(QUE_URL)
  Que.connection = ActiveRecord
  QUE_POOLS[:active_record] = Que.pool

  describe "Que using the ActiveRecord pool" do
    before { Que.pool = QUE_POOLS[:active_record] }

    it_behaves_like "a Que pool"

    it "should use the same connection that ActiveRecord does" do
      begin
        class ActiveRecordJob < Que::Job
          def run
            $pid1 = Que.execute("SELECT pg_backend_pid()").first[:pg_backend_pid]
            $pid2 = Integer(ActiveRecord::Base.connection.select_value("SELECT pg_backend_pid()"))
          end
        end

        ActiveRecordJob.enqueue
        locker = Que::Locker.new

        sleep_until { Integer === $pid1 && Integer === $pid2 }
        $pid1.should == $pid2
      ensure
        $pid1 = $pid2 = nil
        locker.stop if locker
      end
    end

    context "if the connection goes down and is reconnected" do
      before do
        Que::Job.enqueue
        ActiveRecord::Base.connection.reconnect!
      end

      it "should recreate the prepared statements" do
        expect { Que::Job.enqueue }.not_to raise_error

        DB[:que_jobs].count.should == 2
      end

      it "should work properly even in a transaction" do
        ActiveRecord::Base.transaction do
          expect { Que::Job.enqueue }.not_to raise_error
        end

        DB[:que_jobs].count.should == 2
      end

      it "should log this extraordinary event" do
        $logger.messages.clear
        Que::Job.enqueue
        $logger.messages.count.should == 2
        message = JSON.load($logger.messages[1])
        message['lib'].should == 'que'
        message['event'].should == 'reprepare_statement'
        message['name'].should == 'insert_job'
      end
    end

    it "should instantiate args as ActiveSupport::HashWithIndifferentAccess" do
      ArgsJob.enqueue :param => 2
      locker = Que::Locker.new
      sleep_until { $passed_args }
      $passed_args.first[:param].should == 2
      $passed_args.first.should be_an_instance_of ActiveSupport::HashWithIndifferentAccess
      locker.stop
    end

    it "should support Rails' special extensions for times" do
      locker = Que::Locker.new :poll_interval => 0.005.seconds
      sleep 0.01

      run_at = Que::Job.enqueue(:run_at => 1.minute.ago).attrs[:run_at]
      run_at.should be_within(3).of(Time.now - 60)

      sleep_until { DB[:que_jobs].empty? }
      locker.stop
    end

    it "should be able to tell when it's in an ActiveRecord transaction" do
      Que.should_not be_in_transaction
      ActiveRecord::Base.transaction do
        Que.should be_in_transaction
      end
    end
  end
end
