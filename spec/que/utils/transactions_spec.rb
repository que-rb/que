# frozen_string_literal: true

require 'spec_helper'

describe Que::Utils::Transactions do
  it "should be able to commit the transaction successfully" do
    refute Que.in_transaction?
    Que.transaction do
      assert Que.in_transaction?
      Que.execute "INSERT INTO que_jobs (job_class, job_schema_version) VALUES ('MyJobClass', #{Que.job_schema_version});"
      assert Que.in_transaction?
    end
    refute Que.in_transaction?

    assert_equal ['MyJobClass'], jobs_dataset.select_map(:job_class)
  end

  it "should use a transaction to rollback changes in the event of an error" do
    begin
      Que.transaction do
        Que.execute "DROP TABLE que_jobs"
        Que.execute "invalid SQL syntax"
      end
    rescue PG::Error, PG::SyntaxError
    end

    assert DB.table_exists?(:que_jobs)
  end

  it "should rollback correctly in the event of a killed thread" do
    q = Queue.new

    t = Thread.new do
      Que.transaction do
        Que.execute "DROP TABLE que_jobs CASCADE"
        q.push :go!
        sleep
      end
    end

    q.pop
    t.kill
    t.join

    assert DB.table_exists?(:que_jobs)
  end
end
