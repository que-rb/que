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
    it_behaves_like "a multithreaded Que adapter"

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

    it "should safely roll back in-process transactions when using Que.stop!" do
      begin
        class ARInterruptJob < BlockJob
          def run
            ActiveRecord::Base.transaction do
              Que.execute "INSERT INTO que_jobs (job_id, job_class) VALUES (0, 'Que::Job')"
              super
            end
          end
        end

        ARInterruptJob.queue
        Que.mode = :async
        $q1.pop
        Que.stop!

        DB[:que_jobs].where(:job_id => 0).should be_empty
      ensure
        # Que.stop! can affect DB connections in an unpredictable fashion, so
        # force a reconnection for the sake of the other specs.
        ActiveRecord::Base.connection_pool.disconnect!
      end
    end
  end
end
