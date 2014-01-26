require 'spec_helper'

describe "The job polling query" do
  def poll(count, options = {})
    queue   = options[:queue]   || ''
    job_ids = options[:job_ids] || []

    jobs = Que.execute :poll_jobs, [queue, "{#{job_ids.join(',')}}", count]

    returned_job_ids = jobs.map { |j| j[:job_id] }

    ids = Que.execute("SELECT objid FROM pg_locks WHERE locktype = 'advisory' AND pid = pg_backend_pid()")
    ids.map!{|h| h[:objid].to_i}.sort

    ids.sort.should == returned_job_ids.sort

    returned_job_ids
  end

  after do
    Que.execute "SELECT pg_advisory_unlock_all()"
  end

  it "should not fail if there aren't enough jobs to return" do
    id = Que::Job.enqueue.attrs[:job_id]
    poll(5).should == [id]
  end

  it "should return only the requested number of jobs" do
    ids = 5.times.map { Que::Job.enqueue.attrs[:job_id] }
    poll(4).should == ids[0..3]
  end

  it "should return jobs from the given queue" do
    one = Que::Job.enqueue(:queue => 'one').attrs[:job_id]
    two = Que::Job.enqueue(:queue => 'two').attrs[:job_id]

    poll(2, :queue => 'one').should == [one]
  end

  it "should skip jobs with the given job_ids" do
    one = Que::Job.enqueue.attrs[:job_id]
    two = Que::Job.enqueue.attrs[:job_id]

    poll(2, :job_ids => [one]).should == [two]
  end

  it "should only work a job whose scheduled time to run has passed" do
    future1 = Que::Job.enqueue(:run_at => Time.now + 30).attrs[:job_id]
    past    = Que::Job.enqueue(:run_at => Time.now - 30).attrs[:job_id]
    future2 = Que::Job.enqueue(:run_at => Time.now + 30).attrs[:job_id]

    poll(5).should == [past]
  end

  it "should prefer a job with lower priority" do
    # 1 is highest priority.
    [5, 4, 3, 2, 1, 2, 3, 4, 5].map { |p| Que::Job.enqueue :priority => p }

    poll(5).sort.should == DB[:que_jobs].where{priority <= 3}.select_order_map(:job_id)
  end

  it "should prefer a job that was scheduled to run longer ago when priorities are equal" do
    id1 = Que::Job.enqueue(:run_at => Time.now - 30).attrs[:job_id]
    id2 = Que::Job.enqueue(:run_at => Time.now - 60).attrs[:job_id]
    id3 = Que::Job.enqueue(:run_at => Time.now - 30).attrs[:job_id]

    poll(1).should == [id2]
  end

  it "should prefer a job that was queued earlier when priorities and run_ats are equal" do
    run_at = Time.now - 30
    id1 = Que::Job.enqueue(:run_at => run_at).attrs[:job_id]
    id2 = Que::Job.enqueue(:run_at => run_at).attrs[:job_id]
    id3 = Que::Job.enqueue(:run_at => run_at).attrs[:job_id]

    first, second, third = DB[:que_jobs].select_order_map(:job_id)

    poll(2).should == [id1, id2]
  end

  it "should skip jobs that are advisory-locked" do
    id1 = Que::Job.enqueue.attrs[:job_id]
    id2 = Que::Job.enqueue.attrs[:job_id]
    id3 = Que::Job.enqueue.attrs[:job_id]

    begin
      DB.get{pg_advisory_lock(id2)}

      poll(5).should == [id1, id3]
    ensure
      DB.get{pg_advisory_unlock(id2)}
    end
  end
end
