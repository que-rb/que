# frozen_string_literal: true

shared_examples "a Que adapter" do
  it "should be able to execute arbitrary SQL and return indifferent hashes" do
    result = Que.execute("SELECT 1 AS one")
    result.should == [{'one'=>1}]
    result.first[:one].should == 1
  end

  it "should be able to cast boolean results properly" do
    r = Que.execute("SELECT true AS true_value, false AS false_value")
    r.should == [{'true_value' => true, 'false_value' => false}]
  end

  it "should be able to execute multiple SQL statements in one string" do
    Que.execute("SELECT 1 AS one; SELECT 1 AS one")
  end

  it "should be able to queue and work a job" do
    Que::Job.enqueue
    result = Que::Job.work
    result[:event].should == :job_worked
    result[:job][:job_class].should == 'Que::Job'
  end

  it "should yield the same Postgres connection for the duration of the block" do
    Que.adapter.checkout do |conn|
      conn.should be_a PG::Connection
      pid1 = Que.execute "SELECT pg_backend_pid()"
      pid2 = Que.execute "SELECT pg_backend_pid()"
      pid1.should == pid2
    end
  end

  it "should allow nested checkouts" do
    Que.adapter.checkout do |a|
      Que.adapter.checkout do |b|
        a.object_id.should == b.object_id
      end
    end
  end
end
