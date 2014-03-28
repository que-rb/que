require 'spec_helper'

describe Que do
  it ".pool when no connection has been established should raise an error" do
    Que.connection_proc = nil
    proc{Que.pool}.should raise_error RuntimeError, /Que connection not established!/
  end

  it ".use_prepared_statements= should configure whether prepared statements are used" do
    begin
      Que.use_prepared_statements.should be true
      Que.use_prepared_statements = false

      pg = NEW_PG_CONNECTION.call
      Que.connection_proc = proc do |&block|
        block.call(pg)
      end

      $break = true
      Que.execute :job_stats
      proc { pg.exec_prepared("que_job_stats") }.should raise_error PG::InvalidSqlStatementName

      Que.use_prepared_statements = true
      Que.execute :job_stats
      pg.exec_prepared("que_job_stats")
    ensure
      Que.use_prepared_statements = true
    end
  end
end
