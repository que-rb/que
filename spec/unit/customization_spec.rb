require 'spec_helper'

# A few specs to ensure that the ideas given in the customizing_que document
# stay functional.
describe "Customizing Que" do
  it "Cron should allow for easy recurring jobs" do
    class Cron < Que::Job
      def run
        destroy
        self.class.enqueue :run_at => @attrs[:run_at] + 3600
      end
    end

    Cron.enqueue

    run_at = DB[:que_jobs].get(:run_at).to_f

    locker = Que::Locker.new

    sleep_until { DB[:que_jobs].get(:run_at).to_f > run_at }

    DB[:que_jobs].get(:run_at).to_f.should be_within(0.000001).of(run_at + 3600)

    locker.stop
  end

  it "Object#delay should allow for simpler job enqueueing" do
    begin
      class Delayed < Que::Job
        def run(receiver, method, args)
          Marshal.load(receiver).send method, *Marshal.load(args)
        end
      end

      class DelayedAction
        def initialize(receiver)
          @receiver = receiver
        end

        def method_missing(method, *args)
          Delayed.queue Marshal.dump(@receiver), method, Marshal.dump(args)
        end
      end

      class Object
        def delay
          DelayedAction.new(self)
        end
      end

      module MyModule
        class << self
          def blah
            $run = true
          end
        end
      end

      MyModule.delay.blah
      locker = Que::Locker.new

      sleep_until { $run }
      locker.stop
    ensure
      $run = nil
    end
  end

  it "QueueClassic-style jobs should be easy" do
    begin
      class Command < Que::Job
        def run(method, *args)
          receiver, message = method.split('.')
          Object.const_get(receiver).send(message, *args)
        end
      end

      module MyModule
        class << self
          def blah(arg)
            $value = arg
          end
        end
      end

      Command.enqueue "MyModule.blah", "hello world"
      locker = Que::Locker.new
      sleep_until { $value == "hello world" }
      locker.stop
    ensure
      $value = nil
    end
  end

  describe "retaining deleted jobs" do
    before do
      Que.execute "CREATE TABLE finished_jobs AS SELECT * FROM que_jobs LIMIT 0"
    end

    after do
      DB.drop_table? :finished_jobs
    end

    it "with a Ruby override" do
      class MyJobClass < Que::Job
        def destroy
          Que.execute "INSERT INTO finished_jobs SELECT * FROM que_jobs WHERE queue = $1::text AND priority = $2::integer AND run_at = $3::timestamptz AND job_id = $4::bigint", @attrs.values_at(:queue, :priority, :run_at, :job_id)
          super
        end
      end

      class MyJob < MyJobClass
      end

      MyJob.enqueue 1, 'arg1', :priority => 89
      locker = Que::Locker.new

      sleep_until { DB[:finished_jobs].count == 1 }
      job = DB[:finished_jobs].first
      job[:priority].should == 89
      JSON.load(job[:args]).should == [1, 'arg1']

      locker.stop
    end

    it "with a trigger" do
      begin
        Que.execute <<-SQL
          CREATE FUNCTION please_save_my_job()
          RETURNS trigger
          LANGUAGE plpgsql
          AS $$
            BEGIN
              INSERT INTO finished_jobs SELECT (OLD).*;
              RETURN OLD;
            END;
          $$;
        SQL

        Que.execute "CREATE TRIGGER keep_all_my_old_jobs BEFORE DELETE ON que_jobs FOR EACH ROW EXECUTE PROCEDURE please_save_my_job();"

        Que::Job.enqueue 2, 'arg2', :priority => 45
        locker = Que::Locker.new

        sleep_until { DB[:finished_jobs].count == 1 }
        job = DB[:finished_jobs].first
        job[:priority].should == 45
        JSON.load(job[:args]).should == [2, 'arg2']

        locker.stop
      ensure
        DB.drop_trigger :que_jobs, :keep_all_my_old_jobs, :if_exists => true
        DB.drop_function :please_save_my_job, :if_exists => true
      end
    end
  end
end
