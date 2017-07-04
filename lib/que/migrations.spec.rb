# frozen_string_literal: true

require 'spec_helper'

describe Que::Migrations do
  it "should be able to perform migrations up and down" do
    # Migration #1 creates the table with a priority default of 1, migration
    # #2 ups that to 100.

    default = proc do
      result = Que.execute <<-SQL
        select adsrc::integer
        from pg_attribute a
        join pg_class c on c.oid = a.attrelid
        join pg_attrdef on adrelid = attrelid AND adnum = attnum
        where relname = 'que_jobs'
        and attname = 'priority'
      SQL

      result.first[:adsrc]
    end

    assert_equal 100, default.call
    Que::Migrations.migrate! version: 1
    assert_equal 1, default.call
    Que::Migrations.migrate! version: 2
    assert_equal 100, default.call

    # Clean up.
    Que.migrate!(version: Que::Migrations::CURRENT_VERSION)
  end

  it "should be able to get and set the current schema version" do
    assert_equal Que::Migrations::CURRENT_VERSION, Que::Migrations.db_version
    Que::Migrations.set_db_version(59328)
    assert_equal 59328, Que::Migrations.db_version
    Que::Migrations.set_db_version(Que::Migrations::CURRENT_VERSION)
    assert_equal Que::Migrations::CURRENT_VERSION, Que::Migrations.db_version
  end

  it "should be able to cycle the jobs table through all migrations" do
    assert_equal Que::Migrations::CURRENT_VERSION, Que::Migrations.db_version
    Que::Migrations.migrate! version: 0
    assert_equal 0, Que::Migrations.db_version
    assert_equal 0, Que.db_version
    Que::Migrations.migrate!(version: Que::Migrations::CURRENT_VERSION)
    assert_equal Que::Migrations::CURRENT_VERSION, Que::Migrations.db_version

    # The helper on the Que module does the same thing.
    Que.migrate! version: 0
    assert_equal 0, Que::Migrations.db_version
    Que.migrate!(version: Que::Migrations::CURRENT_VERSION)
    assert_equal Que::Migrations::CURRENT_VERSION, Que::Migrations.db_version
  end

  it "should be able to honor the original behavior of Que.drop!" do
    assert DB.table_exists?(:que_jobs)
    Que.drop!
    refute DB.table_exists?(:que_jobs)

    # Clean up.
    Que::Migrations.migrate!(version: Que::Migrations::CURRENT_VERSION)
    assert DB.table_exists?(:que_jobs)
  end

  it "should be able to recognize a que_jobs table at version 0" do
    Que.migrate! version: 0
    DB.create_table(:que_jobs){serial :id} # Dummy Table.
    assert_equal 1, Que::Migrations.db_version
    DB.drop_table(:que_jobs)
    Que.migrate!(version: Que::Migrations::CURRENT_VERSION)
  end

  it "should be able to honor the original behavior of Que.create!" do
    Que.migrate! version: 0
    Que.create!
    assert DB.table_exists?(:que_jobs)
    assert_equal 1, Que::Migrations.db_version

    # Clean up.
    Que::Migrations.migrate!(version: Que::Migrations::CURRENT_VERSION)
    assert DB.table_exists?(:que_jobs)
  end

  it "down migrations should precisely undo what the up migrations did" do
    Que.migrate! version: 0
    versions = (1..Que::Migrations::CURRENT_VERSION).to_a

    Que.checkout do |conn|
      versions.each do |version|
        original_snapshot = PGExaminer.examine(conn)

        Que.migrate! version: version
        Que.migrate! version: version - 1

        new_snapshot = PGExaminer.examine(conn)
        diff = original_snapshot.diff(new_snapshot)

        assert_empty diff, "Migration ##{version} didn't precisely undo itself!"

        Que.migrate! version: version
      end
    end
  end

  describe "migration #4" do
    it "should handle last_errors without a backtrace"

    it "should correctly migrate data down and up" do
      DB[:que_jobs].insert(
        id: 1,
        job_class: 'Que::Job',
        queue: 'default',
        data: JSON.dump(args: [78, {arg1: true, arg2: 'a'}]),
      )

      DB[:que_jobs].insert(
        id: 2,
        job_class: 'Que::Job',
        queue: 'other_queue',
        data: JSON.dump(args: [89, {arg1: true, arg2: 'b'}]),
        last_error_message: "Error: an error message",
        last_error_backtrace: "line 1\nline 2\nline 3",
      )

      Que::Migrations.migrate! version: 3

      assert_equal(
        [
          {
            job_id: 1,
            args: [78, {arg1: true, arg2: 'a'}],
            queue: '',
            last_error: nil,
          },
          {
            job_id: 2,
            args: [89, {arg1: true, arg2: 'b'}],
            queue: 'other_queue',
            last_error: "Error: an error message\nline 1\nline 2\nline 3",
          },
        ],
        DB[:que_jobs].
          order(:job_id).
          select(:job_id, :args, :queue, :last_error).
          all{|a| a[:args] = JSON.parse(a[:args], symbolize_names: true)}
      )

      # Add a few rows where args is not an array, to make sure the migration
      # handles those. This behavior was never supported, so it shouldn't
      # happen, but better safe than sorry.

      # The table primary key is different at this migration, so provide a
      # returning clause so that Sequel doesn't get confused.
      DB[:que_jobs].returning(:job_id).insert(
        job_id: 3,
        job_class: 'Que::Job',
        args: JSON.dump({arg1: true, arg2: 'a'}),
      )

      DB[:que_jobs].returning(:job_id).insert(
        job_id: 4,
        job_class: 'Que::Job',
        args: '5',
      )

      Que::Migrations.migrate! version: 4

      assert_equal(
        [
          {
            id: 1,
            is_processed: false,
            data: {args: [78, {arg1: true, arg2: 'a'}]},
            queue: 'default',
            last_error_message: nil,
            last_error_backtrace: nil,
          },
          {
            id: 2,
            is_processed: false,
            data: {args: [89, {arg1: true, arg2: 'b'}]},
            queue: 'other_queue',
            last_error_message: "Error: an error message",
            last_error_backtrace: "line 1\nline 2\nline 3",
          },
          {
            id: 3,
            is_processed: false,
            data: {args: [{arg1: true, arg2: 'a'}]},
            queue: 'default',
            last_error_message: nil,
            last_error_backtrace: nil,
          },
          {
            id: 4,
            is_processed: false,
            data: {args: [5]},
            queue: 'default',
            last_error_message: nil,
            last_error_backtrace: nil,
          },
        ],
        DB[:que_jobs].
          order(:id).
          select(
            :id, :is_processed, :data, :queue,
            :last_error_message, :last_error_backtrace,
          ).
          all{|a| a[:data] = JSON.parse(a[:data], symbolize_names: true)}
      )
    end
  end
end
