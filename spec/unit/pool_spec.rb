require 'spec_helper'

describe "Managing the Worker pool" do
  it "should log mode changes" do
    Que.mode = :off
    $logger.messages.should == ["[Que] Set mode to :off"]
  end

  it "Que.stop! should do nothing if there are no workers running" do
    Que::Worker.workers.should be_empty
    Que.stop!
  end

  describe "Que.mode = :sync" do
    it "should make jobs run in the same thread as they are queued" do
      Que.mode = :sync

      ArgsJob.queue(5, :testing => "synchronous").should be_an_instance_of ArgsJob
      $passed_args.should == [5, {'testing' => "synchronous"}]
      DB[:que_jobs].count.should be 0

      $logger.messages.length.should be 2
      $logger.messages[0].should == "[Que] Set mode to :sync"
      $logger.messages[1].should =~ /\A\[Que\] Worked job in/
    end

    it "should not affect jobs that are queued with specific run_ats" do
      Que.mode = :sync

      ArgsJob.queue(5, :testing => "synchronous", :run_at => Time.now + 60)
      DB[:que_jobs].select_map(:job_class).should == ["ArgsJob"]
    end

    it "then Que.stop! should do nothing" do
      Que::Worker.workers.should be_empty
      Que.stop!
    end
  end

  describe "Que.mode = :async" do
    it "should spin up 4 workers" do
      Que.mode = :async
      Que.worker_count.should be 4
      sleep_until { Que::Worker.workers.all?(&:sleeping?) }
    end

    it "should not affect the number of workers if a worker_count has already been set" do
      Que.worker_count = 1
      Que.mode = :async
      Que.worker_count.should be 1
    end

    it "then Que.worker_count = 2 should gracefully decrease the number of workers" do
      Que.mode = :async
      workers = Que::Worker.workers.dup
      workers.count.should be 4

      Que.worker_count = 2
      Que.worker_count.should be 2
      sleep_until { Que::Worker.workers.all?(&:sleeping?) }

      workers[0..1].should == Que::Worker.workers
      workers[2..3].each do |worker|
        worker.should be_an_instance_of Que::Worker
        worker.thread.status.should == false
      end
    end

    it "then Que.worker_count = 6 should gracefully increase the number of workers" do
      Que.mode = :async
      workers = Que::Worker.workers.dup
      workers.count.should be 4

      Que.worker_count = 6
      Que.worker_count.should be 6
      sleep_until { workers.all?(&:sleeping?) }

      workers.should == Que::Worker.workers[0..3]
    end

    it "then Que.mode = :off should gracefully shut down workers" do
      Que.mode = :async
      workers = Que::Worker.workers.dup
      workers.count.should be 4

      Que.mode = :off
      Que.worker_count.should be 0

      workers.count.should be 4
      workers.each { |worker| worker.thread.status.should be false }
    end

    it "then Que::Worker.wake! should wake up a single worker" do
      Que.mode = :async
      sleep_until { Que::Worker.workers.all? &:sleeping? }

      BlockJob.queue
      Que::Worker.wake!

      $q1.pop
      Que::Worker.workers.first.should be_working
      Que::Worker.workers[1..3].each { |w| w.should be_sleeping }
      DB[:que_jobs].count.should be 1
      $q2.push nil

      sleep_until { Que::Worker.workers.all? &:sleeping? }
      DB[:que_jobs].count.should be 0
    end

    it "then Que::Worker.wake_all! should wake up all workers" do
      # This spec requires at least four connections.
      Que.adapter = QUE_ADAPTERS[:connection_pool]

      Que.mode = :async
      sleep_until { Que::Worker.workers.all? &:sleeping? }

      4.times { BlockJob.queue }
      Que::Worker.wake_all!
      4.times { $q1.pop }

      Que::Worker.workers.each{ |worker| worker.should be_working }
      4.times { $q2.push nil }

      sleep_until { Que::Worker.workers.all? &:sleeping? }
      DB[:que_jobs].count.should be 0
    end if QUE_ADAPTERS[:connection_pool]

    it "should poke a worker every Que.sleep_period seconds" do
      begin
        Que.mode = :async

        sleep_until { Que::Worker.workers.all? &:sleeping? }
        Que.sleep_period = 0.01 # 10 ms
        Que::Job.queue
        sleep_until { DB[:que_jobs].count == 0 }
      ensure
        Que.sleep_period = nil
      end
    end

    it "then Que.stop! should interrupt all running jobs" do
      begin
        # Que.stop! can unpredictably affect connections, which may affect
        # other tests, so use a new one.
        pg = NEW_PG_CONNECTION.call
        Que.connection = pg

        BlockJob.queue
        Que.mode = :async
        $q1.pop
        Que.stop!
      ensure
        pg.close if pg
      end
    end
  end
end
