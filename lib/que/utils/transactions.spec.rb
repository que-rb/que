# frozen_string_literal: true

require 'spec_helper'

describe Que::Utils::Transactions do
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
        Que.execute "DROP TABLE que_jobs"
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
