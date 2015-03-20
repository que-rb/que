require 'spec_helper'

describe Que, '.transaction' do
  it "should use a transaction to rollback changes in the event of an error" do
    proc do
      Que.transaction do
        Que.execute "DROP TABLE que_jobs"
        Que.execute "invalid SQL syntax"
      end
    end.should raise_error(PG::Error)

    DB.table_exists?(:que_jobs).should be true
  end

  unless RUBY_VERSION.start_with?('1.9')
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

      DB.table_exists?(:que_jobs).should be true
    end
  end
end
