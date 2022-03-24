# frozen_string_literal: true

require 'spec_helper'

describe Que::Migrations do
  it "should be able to perform migrations up and down" do
    # Migration #1 creates the table with a priority default of 1, migration
    # #2 ups that to 100.

    default = proc do
      result = Que.execute <<-SQL
        select pg_get_expr(adbin, adrelid)::integer AS adsrc
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
        original_snapshot = PGExaminer.examine(conn.wrapped_connection)

        Que.migrate! version: version
        Que.migrate! version: version - 1

        new_snapshot = PGExaminer.examine(conn.wrapped_connection)
        diff = original_snapshot.diff(new_snapshot)

        assert_empty diff, "Migration ##{version} didn't precisely undo itself!"

        Que.migrate! version: version
      end
    end
  end

  describe "migration #4" do
    before do
      Que::Migrations.migrate!(version: 4)
    end

    after do
      DB[:que_jobs].delete
      Que::Migrations.migrate!(version: Que::Migrations::CURRENT_VERSION)
    end

    def version_3
      Que::Migrations.migrate! version: 3
      yield
      Que::Migrations.migrate! version: 4
    end

    def assert_round_trip_migration(v3: {}, v4: {})
      v4_default = {id: 1, job_class: 'Que::Job', queue: 'default', data: {}, args: [], last_error_message: nil, last_error_backtrace: nil}
      v3_default = {job_id: 1, job_class: 'Que::Job', queue: '', args: [], last_error: nil}

      DB[:que_jobs].insert(
        v4_default.merge(v4).tap { |j|
          j[:args] = JSON.dump(j[:args])
          j[:data] = JSON.dump(j[:data])
        }
      )

      version_3 do
        assert_equal(
          v3_default.merge(v3),
          DB[:que_jobs].
            where(job_id: 1).
            select(:job_class, :job_id, :args, :queue, :last_error).
            first
        )
      end

      assert_equal(
        v4_default.merge(v4),
        DB[:que_jobs].
          where(id: 1).
          select(:id, :job_class, :args, :data, :queue, :last_error_message, :last_error_backtrace).
          first
      )
    end

    def assert_up_migration(v3: {}, v4: {})
      v4_default = {id: 1, job_class: 'Que::Job', queue: 'default', data: {}, args: [], last_error_message: nil, last_error_backtrace: nil}
      v3_default = {job_id: 1, job_class: 'Que::Job', queue: '', args: [], last_error: nil}

      version_3 do
        # The table primary key is different at this schema version, so provide a
        # returning clause so that Sequel doesn't get confused.
        DB[:que_jobs].returning(:job_id).insert(v3_default.merge(v3).tap{|j| j[:args] = JSON.generate(j[:args], quirks_mode: true)})
      end

      assert_equal(
        v4_default.merge(v4),
        DB[:que_jobs].
          where(id: 1).
          select(:id, :job_class, :data, :args, :queue, :last_error_message, :last_error_backtrace).
          first
      )
    end

    it "should correctly migrate data down and up" do
      assert_round_trip_migration
    end

    it "should correctly migrate error data down and up" do
      assert_round_trip_migration(
        v3: {last_error: "Error: an error message\nline 1\nline 2\nline 3"},
        v4: {last_error_message: "Error: an error message", last_error_backtrace: "line 1\nline 2\nline 3"},
      )
    end

    it "should correctly migrate up jobs with an error message but no backtrace" do
      assert_round_trip_migration(
        v3: {last_error: "Error without a backtrace!"},
        v4: {
          last_error_message: "Error without a backtrace!",
          last_error_backtrace: nil,
        },
      )
    end

    describe "when the args column has unusual values" do
      it "should correctly migrate up jobs whose args are hashes instead of arrays" do
        assert_up_migration(
          v3: {args: {arg1: true, arg2: 'a'}},
          v4: {args: [{arg1: true, arg2: 'a'}]},
        )
      end

      it "should correctly migrate up jobs whose args are scalar strings instead of arrays" do
        assert_up_migration(
          v3: {args: "arg1"},
          v4: {args: ["arg1"]},
        )
      end

      it "should correctly migrate up jobs whose args are scalar integers instead of arrays" do
        assert_up_migration(
          v3: {args: 5},
          v4: {args: [5]},
        )
      end
    end

    it "when the last_error_message is longer than 500 characters" do
      assert_up_migration(
        v3: {last_error: "a" * 501 + "\na"},
        v4: {last_error_message: "a" * 500, last_error_backtrace: "a"},
      )
    end

    it "when the last_error_backtrace is longer than 10,000 characters" do
      assert_up_migration(
        v3: {last_error: "a\n" + "a" * 10_001},
        v4: {last_error_message: "a", last_error_backtrace: "a" * 10_000},
      )
    end

    it "when migrating down should remove finished and expired jobs so that they aren't run repeatedly" do
      Que::Migrations.migrate!(version: Que::Migrations::CURRENT_VERSION)
      a, b, c = 3.times.map { Que::Job.enqueue.que_attrs[:id] }

      jobs_dataset.where(id: a).update(finished_at: Time.now)
      jobs_dataset.where(id: b).update(finished_at: Time.now)

      version_3 do
        assert_equal [c], jobs_dataset.select_map(:job_id)
      end

      assert_equal [c], jobs_dataset.select_map(:id)

      Que::Migrations.migrate!(version: Que::Migrations::CURRENT_VERSION)
    end
  end
end
