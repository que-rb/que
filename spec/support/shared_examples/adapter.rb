shared_examples "a Que adapter" do
  it "should be able to execute arbitrary SQL and return indifferent hashes" do
    result = Que.execute("SELECT 1 AS one")
    result.should == [{'one'=>'1'}]
    result.first[:one].should == '1'
  end

  it "should be able to queue and work a job" do
    Que::Job.queue
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

  it "should allow multiple threads to check out their own connections" do
    one = nil
    two = nil

    q1, q2 = Queue.new, Queue.new

    thread = Thread.new do
      Que.adapter.checkout do |conn|
        q1.push nil
        q2.pop
        one = conn.object_id
      end
    end

    Que.adapter.checkout do |conn|
      q1.pop
      q2.push nil
      two = conn.object_id
    end

    thread.join
    one.should_not == two
  end

  it "should allow multiple workers to complete jobs simultaneously" do
    BlockJob.queue
    worker_1 = Que::Worker.new
    $q1.pop

    Que::Job.queue
    DB[:que_jobs].count.should be 2

    worker_2 = Que::Worker.new
    sleep_until { worker_2.sleeping? }
    DB[:que_jobs].count.should be 1

    $q2.push nil
    sleep_until { worker_1.sleeping? }
    DB[:que_jobs].count.should be 0
  end
end
