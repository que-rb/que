require 'spec_helper'

describe Que::Migrations do
  it "should be able to perform migrations up and down" do
    # Migration #1 creates the table with a priority default of 1, migration
    # #2 ups that to 100.

    default = proc do
      result = Que.execute <<-SQL
        select adsrc
        from pg_attribute a
        join pg_class c on c.oid = a.attrelid
        join pg_attrdef on adrelid = attrelid AND adnum = attnum
        where relname = 'que_jobs'
        and attname = 'priority'
      SQL

      result.first['adsrc'].to_i
    end

    default.call.should == 100
    Que::Migrations.migrate! :version => 1
    default.call.should == 1
    Que::Migrations.migrate! :version => 2
    default.call.should == 100

    # Clean up.
    Que.migrate!
  end

  it "should be able to get and set the current schema version" do
    Que::Migrations.db_version.should == Que::Migrations::CURRENT_VERSION
    Que::Migrations.set_db_version(59328)
    Que::Migrations.db_version.should == 59328
    Que::Migrations.set_db_version(Que::Migrations::CURRENT_VERSION)
    Que::Migrations.db_version.should == Que::Migrations::CURRENT_VERSION
  end

  it "should be able to cycle the jobs table all the way between nonexistent and current without error" do
    Que::Migrations.db_version.should == Que::Migrations::CURRENT_VERSION
    Que::Migrations.migrate! :version => 0
    Que::Migrations.db_version.should == 0
    Que::Migrations.migrate!
    Que::Migrations.db_version.should == Que::Migrations::CURRENT_VERSION

    # The helper on the Que module does the same thing.
    Que.migrate! :version => 0
    Que::Migrations.db_version.should == 0
    Que.migrate!
    Que::Migrations.db_version.should == Que::Migrations::CURRENT_VERSION
  end

  it "should be able to honor the initial behavior of Que.drop!" do
    DB.table_exists?(:que_jobs).should be true
    Que.drop!
    DB.table_exists?(:que_jobs).should be false

    # Clean up.
    Que::Migrations.migrate!
    DB.table_exists?(:que_jobs).should be true
  end

  it "should be able to recognize a que_jobs table created before the versioning system" do
    DB.drop_table :que_jobs
    DB.create_table(:que_jobs){serial :id} # Dummy Table.
    Que::Migrations.db_version.should == 1
    DB.drop_table(:que_jobs)
    Que::Migrations.migrate!
  end

  it "should be able to honor the initial behavior of Que.create!" do
    DB.drop_table :que_jobs
    Que.create!
    DB.table_exists?(:que_jobs).should be true
    Que::Migrations.db_version.should == 1

    # Clean up.
    Que::Migrations.migrate!
    DB.table_exists?(:que_jobs).should be true
  end

  it "should use transactions to protect its migrations from errors" do
    proc do
      Que::Migrations.transaction do
        Que.execute "DROP TABLE que_jobs"
        Que.execute "invalid SQL syntax"
      end
    end.should raise_error(PG::SyntaxError)

    DB.table_exists?(:que_jobs).should be true
  end

  # In Ruby 1.9, it's impossible to tell inside an ensure block whether the
  # currently executing thread has been killed.
  unless RUBY_VERSION.start_with?('1.9')
    it "should use transactions to protect its migrations from killed threads" do
      q = Queue.new

      t = Thread.new do
        Que::Migrations.transaction do
          Que.execute "DROP TABLE que_jobs"
          q.push :go!
          sleep
        end
      end

      q.pop
      t.kill
      t.join

      DB.table_exists?(:que_jobs).should be true
    end
  end

  it "should be able to tell when it's already in a transaction" do
    Que.adapter = QUE_ADAPTERS[:connection_pool]
    Que::Migrations.should_not be_in_transaction
    QUE_SPEC_CONNECTION_POOL.with do |conn|
      conn.async_exec "BEGIN"
      Que::Migrations.should be_in_transaction
      conn.async_exec "COMMIT"
    end
  end if QUE_ADAPTERS[:connection_pool]

  it "should be able to tell when it's in a Sequel transaction" do
    Que.adapter = QUE_ADAPTERS[:sequel]
    Que::Migrations.should_not be_in_transaction
    SEQUEL_ADAPTER_DB.transaction do
      Que::Migrations.should be_in_transaction
    end
  end if QUE_ADAPTERS[:sequel]

  it "should be able to tell when it's in an ActiveRecord transaction" do
    Que.adapter = QUE_ADAPTERS[:active_record]
    Que::Migrations.should_not be_in_transaction
    ActiveRecord::Base.transaction do
      Que::Migrations.should be_in_transaction
    end
  end if QUE_ADAPTERS[:active_record]
end
