# frozen_string_literal: true

require 'spec_helper'

# A few specs to ensure that the ideas given in the customizing_que document
# stay functional.
describe "Customizing Que" do
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
      locker = Que::Locker.new

      sleep_until { $run }
      locker.stop!
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
      locker.stop!
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
          Que.execute "INSERT INTO finished_jobs SELECT * FROM que_jobs WHERE priority = $1::integer AND run_at = $2::timestamptz AND job_id = $3::bigint", @attrs.values_at(:priority, :run_at, :job_id)
          super
        end
      end

      class MyJob < MyJobClass
      end

      MyJob.enqueue 1, 'arg1', priority: 89
      locker = Que::Locker.new

      sleep_until { DB[:finished_jobs].count == 1 }
      job = DB[:finished_jobs].first
      job[:priority].should == 89
      JSON.load(job[:args]).should == [1, 'arg1']

      locker.stop!
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

        Que::Job.enqueue 2, 'arg2', priority: 45
        locker = Que::Locker.new

        sleep_until { DB[:finished_jobs].count == 1 }
        job = DB[:finished_jobs].first
        job[:priority].should == 45
        JSON.load(job[:args]).should == [2, 'arg2']

        locker.stop!
      ensure
        DB.drop_trigger :que_jobs, :keep_all_my_old_jobs, if_exists: true
        DB.drop_function :please_save_my_job, if_exists: true
      end
    end
  end

  describe "with different columns" do
    it "with an additional column makes that column available to the job" do
      begin
        DB.alter_table :que_jobs do
          add_column :additional_column, :text, default: 'additional_column_default_value'
        end

        class AdditionalColumnJob < Que::Job
          def run(*args)
            $additional_column_value = @attrs[:additional_column]
          end
        end

        AdditionalColumnJob.enqueue

        locker = Que::Locker.new
        sleep_until { $additional_column_value == "additional_column_default_value" }
        locker.stop!
      ensure
        DB.alter_table :que_jobs do
          drop_column :additional_column
        end
        $additional_column_value = nil
      end
    end

    # # Waiting on Postgres to get a bit smarter with regards to implicitly
    # # casting JSON to JSONB.

    # it "when the args hash is stored as JSONB should deserialize it fine" do
    #   if Que.checkout(&:server_version) >= 90400 # JSONB only in 9.4+
    #     begin
    #       DB.transaction do
    #         DB.alter_table :que_jobs do
    #           set_column_default :args, nil
    #         end

    #         DB.alter_table :que_jobs do
    #           set_column_type :args, :jsonb, using: Sequel.cast(Sequel.cast(:args, :text), :jsonb)
    #           set_column_default :args, Sequel.lit("'[]'::jsonb")
    #         end
    #       end

    #       ArgsJob.enqueue 2, 'arg2', priority: 45

    #       locker = Que::Locker.new

    #       # sleep_until { $passed_args == [2, 'arg2', {priority: 45}] }
    #       locker.stop!
    #     ensure
    #       DB.transaction do
    #         DB.alter_table :que_jobs do
    #           set_column_default :args, nil
    #         end

    #         DB.alter_table :que_jobs do
    #           set_column_type :args, :json, using: Sequel.cast(Sequel.cast(:args, :text), :json)
    #           set_column_default :args, Sequel.lit("'[]'::json")
    #         end
    #       end
    #     end
    #   end
    # end
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
                FROM  que_jobs
                WHERE priority = $1::smallint
                AND   run_at   = $2::timestamptz
                AND   job_id   = $3::bigint
                RETURNING *
              )
              INSERT INTO failed_jobs
                SELECT * FROM failed;
            SQL

            Que.execute sql, @attrs.values_at(:priority, :run_at, :job_id)

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

        locker = Que::Locker.new
        sleep_until { DB[:failed_jobs].count > 0 }
        locker.stop!

        $retry_job_args.should == [1, 'arg1', {other_arg: 'blah'}]

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
