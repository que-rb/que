require 'spec_helper'

# A few specs to ensure that the ideas given in the customizing_que document
# stay functional.
describe "Customizing Que" do
  it "Cron should allow for easy recurring jobs" do
    begin
      class CronJob < Que::Job
        # Default repetition interval in seconds. Can be overridden in
        # subclasses. Can use 1.minute if using Rails.
        INTERVAL = 60

        attr_reader :start_at, :end_at, :run_again_at, :time_range

        def _run
          args = attrs[:args].first
          @start_at, @end_at = Time.at(args.delete('start_at')), Time.at(args.delete('end_at'))
          @run_again_at = @end_at + self.class::INTERVAL
          @time_range = @start_at...@end_at

          super

          args['start_at'] = @end_at.to_f
          args['end_at']   = @run_again_at.to_f
          self.class.enqueue(args, run_at: @run_again_at)
        end
      end

      class MyCronJob < CronJob
        INTERVAL = 1.5

        def run(args)
          $args       = args.dup
          $time_range = time_range
        end
      end

      t = (Time.now - 1000).to_f.round(6)
      MyCronJob.enqueue :start_at => t, :end_at => t + 1.5, :arg => 4

      $args.should be nil
      $time_range.should be nil

      Que::Job.work

      $args.should == {'arg' => 4}
      $time_range.begin.to_f.round(6).should be_within(0.000001).of t
      $time_range.end.to_f.round(6).should be_within(0.000001).of t + 1.5
      $time_range.exclude_end?.should be true

      DB[:que_jobs].get(:run_at).to_f.round(6).should be_within(0.000001).of(t + 3.0)
      args = JSON.parse(DB[:que_jobs].get(:args)).first
      args.keys.should == ['arg', 'start_at', 'end_at']
      args['arg'].should == 4
      args['start_at'].should be_within(0.000001).of(t + 1.5)
      args['end_at'].should be_within(0.000001).of(t + 3.0)
    ensure
      $args       = nil
      $time_range = nil
    end
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
          Delayed.enqueue Marshal.dump(@receiver), method, Marshal.dump(args)
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
      Que::Job.work

      $run.should be true
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
      Que::Job.work

      $value.should == "hello world"
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
      Que::Job.work

      DB[:finished_jobs].count.should == 1
      job = DB[:finished_jobs].first
      job[:priority].should == 89
      JSON.load(job[:args]).should == [1, 'arg1']
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
        Que::Job.work

        DB[:finished_jobs].count.should == 1
        job = DB[:finished_jobs].first
        job[:priority].should == 45
        JSON.load(job[:args]).should == [2, 'arg2']
      ensure
        DB.drop_trigger :que_jobs, :keep_all_my_old_jobs, :if_exists => true
        DB.drop_function :please_save_my_job, :if_exists => true
      end
    end
  end

  describe "not retrying specific failed jobs" do
    before do
      Que.execute "CREATE TABLE failed_jobs AS SELECT * FROM que_jobs LIMIT 0"
    end

    after do
      DB.drop_table? :failed_jobs
    end

    it "should be easily achievable with a module" do
      begin
        module SkipRetries
          def run(*args)
            super
          rescue
            sql = <<-SQL
              WITH failed AS (
                DELETE
                FROM   que_jobs
                WHERE  queue    = $1::text
                AND    priority = $2::smallint
                AND    run_at   = $3::timestamptz
                AND    job_id   = $4::bigint
                RETURNING *
              )
              INSERT INTO failed_jobs
                SELECT * FROM failed;
            SQL

            Que.execute sql, @attrs.values_at(:queue, :priority, :run_at, :job_id)

            raise
          end
        end

        class SkipRetryJob < Que::Job
          prepend SkipRetries

          def run(*args)
            $retry_job_args = args
            raise "Fail!"
          end
        end

        SkipRetryJob.enqueue 1, 'arg1', :other_arg => 'blah'
        Que::Job.work

        $retry_job_args.should == [1, 'arg1', {'other_arg' => 'blah'}]

        DB[:que_jobs].count.should == 0
        DB[:failed_jobs].count.should == 1

        job = DB[:failed_jobs].first
        JSON.parse(job[:args]).should == [1, 'arg1', {'other_arg' => 'blah'}]
        job[:job_class].should == 'SkipRetryJob'
      ensure
        $retry_job_args = nil
      end
    end
  end
end
