require 'spec_helper'

describe "Managing the Worker pool" do
  it "should log mode changes" do
    Que.mode = :sync
    Que.mode = :off
    Que.mode = :off

    $logger.messages.count.should be 3
    m1, m2, m3 = $logger.messages.map { |m| JSON.load(m) }

    m1['event'].should == 'mode_change'
    m1['value'].should == 'sync'

    m2['event'].should == 'mode_change'
    m2['value'].should == 'off'

    m3['event'].should == 'mode_change'
    m3['value'].should == 'off'
  end

  describe "Que.mode=" do
    describe ":off" do
      it "with worker_count 0 should not hit the db" do
        Que.connection = nil
        Que.worker_count = 0
        Que.mode = :off
        sleep_until { Que::Worker.workers.all? &:sleeping? }
        Que::Worker.workers.map{|w| [w.state, w.thread.status]}.should == []
      end

      it "with worker_count > 0 should not hit the db" do
        Que.connection = nil
        Que.mode = :off
        Que.worker_count = 5
        sleep_until { Que::Worker.workers.all? &:sleeping? }
        Que::Worker.workers.map{|w| [w.state, w.thread.status]}.should == [[:sleeping, 'sleep']] * 5
      end
    end

    describe ":sync" do
      it "with worker_count 0 should not hit the db" do
        Que.connection = nil
        Que.worker_count = 0
        Que.mode = :sync
        sleep_until { Que::Worker.workers.all? &:sleeping? }
        Que::Worker.workers.map{|w| [w.state, w.thread.status]}.should == []
      end

      it "with worker_count > 0 should not hit the db" do
        Que.connection = nil
        Que.mode = :sync
        Que.worker_count = 5
        sleep_until { Que::Worker.workers.all? &:sleeping? }
        Que::Worker.workers.map{|w| [w.state, w.thread.status]}.should == [[:sleeping, 'sleep']] * 5
      end

      it "should make jobs run in the same thread as they are queued" do
        Que.mode = :sync

        ArgsJob.enqueue(5, :testing => "synchronous").should be_an_instance_of ArgsJob
        $passed_args.should == [5, {:testing => "synchronous"}]
        DB[:que_jobs].count.should be 0
      end

      it "should work fine with enqueuing jobs without a DB connection" do
        Que.connection = nil
        Que.mode = :sync

        ArgsJob.enqueue(5, :testing => "synchronous").should be_an_instance_of ArgsJob
        $passed_args.should == [5, {:testing => "synchronous"}]
      end

      it "should not affect jobs that are queued with specific run_ats" do
        Que.mode = :sync

        ArgsJob.enqueue(5, :testing => "synchronous", :run_at => Time.now + 60)
        DB[:que_jobs].select_map(:job_class).should == ["ArgsJob"]
      end
    end

    describe ":async" do
      it "with worker_count 0 should not hit the db" do
        Que.connection = nil
        Que.worker_count = 0
        Que.mode = :async
        Que::Worker.workers.map{|w| [w.state, w.thread.status]}.should == []
      end

      it "with worker_count > 0 should hit the db" do
        Que::Job.enqueue
        Que.worker_count = 5
        Que.mode = :async
        sleep_until { Que::Worker.workers.all? &:sleeping? }
        DB[:que_jobs].count.should == 0
        Que::Worker.workers.map{|w| [w.state, w.thread.status]}.should == [[:sleeping, 'sleep']] * 5
      end

      it "should wake a worker every Que.wake_interval seconds" do
        Que.worker_count = 4
        Que.mode = :async
        sleep_until { Que::Worker.workers.all? &:sleeping? }
        Que.wake_interval = 0.01 # 10 ms
        Que::Job.enqueue
        sleep_until { DB[:que_jobs].count == 0 }
      end

      it "should work jobs in the queue defined by QUE_QUEUE" do
        begin
          Que::Job.enqueue 1
          Que::Job.enqueue 2, :queue => 'my_queue'

          ENV['QUE_QUEUE'] = 'my_queue'

          Que.mode = :async
          Que.worker_count = 2

          sleep_until { Que::Worker.workers.all? &:sleeping? }
          DB[:que_jobs].count.should be 1

          job = DB[:que_jobs].first
          job[:queue].should == ''
          job[:args].should == '[1]'
        ensure
          ENV.delete('QUE_QUEUE')
        end
      end
    end
  end

  describe "Que.worker_count=" do
    describe "when the mode is :off" do
      it "should scale the number of sleeping workers without hitting the DB" do
        Que.connection = nil
        Que.mode = :off
        Que::Worker.workers.count.should == 0

        Que.worker_count = 4
        sleep_until { Que::Worker.workers.all?(&:sleeping?) }
        Que::Worker.workers.map{|w| [w.state, w.thread.status]}.should == [[:sleeping, 'sleep']] * 4
        Que::Worker.workers.count.should == 4

        Que.worker_count = 6
        sleep_until { Que::Worker.workers.all?(&:sleeping?) }
        Que::Worker.workers.map{|w| [w.state, w.thread.status]}.should == [[:sleeping, 'sleep']] * 6
        Que::Worker.workers.count.should == 6

        Que.worker_count = 2
        sleep_until { Que::Worker.workers.all?(&:sleeping?) }
        Que::Worker.workers.map{|w| [w.state, w.thread.status]}.should == [[:sleeping, 'sleep']] * 2
        Que::Worker.workers.count.should == 2

        Que.worker_count = 0
        sleep_until { Que::Worker.workers.all?(&:sleeping?) }
        Que::Worker.workers.map{|w| [w.state, w.thread.status]}.should == []
        Que::Worker.workers.count.should == 0
      end
    end

    describe "when the mode is :sync" do
      it "should scale the number of sleeping workers without hitting the DB" do
        Que.connection = nil
        Que.mode = :sync
        Que::Worker.workers.count.should == 0

        Que.worker_count = 4
        sleep_until { Que::Worker.workers.all?(&:sleeping?) }
        Que::Worker.workers.map{|w| [w.state, w.thread.status]}.should == [[:sleeping, 'sleep']] * 4
        Que::Worker.workers.count.should == 4

        Que.worker_count = 6
        sleep_until { Que::Worker.workers.all?(&:sleeping?) }
        Que::Worker.workers.map{|w| [w.state, w.thread.status]}.should == [[:sleeping, 'sleep']] * 6
        Que::Worker.workers.count.should == 6

        Que.worker_count = 2
        sleep_until { Que::Worker.workers.all?(&:sleeping?) }
        Que::Worker.workers.map{|w| [w.state, w.thread.status]}.should == [[:sleeping, 'sleep']] * 2
        Que::Worker.workers.count.should == 2

        Que.worker_count = 0
        sleep_until { Que::Worker.workers.all?(&:sleeping?) }
        Que::Worker.workers.map{|w| [w.state, w.thread.status]}.should == []
        Que::Worker.workers.count.should == 0
      end
    end

    describe "when the mode is :async" do
      it "should start hitting the DB when transitioning to a non-zero value" do
        Que.mode = :async
        Que::Job.enqueue
        Que.worker_count = 4
        sleep_until { Que::Worker.workers.all?(&:sleeping?) }
        DB[:que_jobs].count.should == 0
      end

      it "should stop hitting the DB when transitioning to zero" do
        Que.mode = :async
        Que.worker_count = 4
        sleep_until { Que::Worker.workers.all?(&:sleeping?) }
        Que.connection = nil
        Que.worker_count = 0
        $logger.messages.map{|m| JSON.load(m).values_at('event', 'value')}.should ==
          [['mode_change', 'async'], ['worker_count_change', '4']] + [['job_unavailable', nil]] * 4 + [['worker_count_change', '0']]
      end

      it "should be able to scale down the number of workers gracefully" do
        Que.mode = :async
        Que.worker_count = 4

        workers = Que::Worker.workers.dup
        workers.count.should be 4
        sleep_until { Que::Worker.workers.all?(&:sleeping?) }

        Que.worker_count = 2
        Que::Worker.workers.count.should be 2
        sleep_until { Que::Worker.workers.all?(&:sleeping?) }

        workers[0..1].should == Que::Worker.workers
        workers[2..3].each do |worker|
          worker.should be_an_instance_of Que::Worker
          worker.thread.status.should == false
        end

        $logger.messages.map{|m| JSON.load(m).values_at('event', 'value')}.should ==
          [['mode_change', 'async'], ['worker_count_change', '4']] + [['job_unavailable', nil]] * 4 + [['worker_count_change', '2']]
      end

      it "should be able to scale up the number of workers gracefully" do
        Que.mode = :async
        Que.worker_count = 4
        workers = Que::Worker.workers.dup
        workers.count.should be 4

        sleep_until { Que::Worker.workers.all?(&:sleeping?) }
        Que.worker_count = 6
        Que::Worker.workers.count.should be 6
        sleep_until { Que::Worker.workers.all?(&:sleeping?) }

        workers.should == Que::Worker.workers[0..3]

        $logger.messages.map{|m| JSON.load(m).values_at('event', 'value')}.should ==
          [['mode_change', 'async'], ['worker_count_change', '4']] + [['job_unavailable', nil]] * 4 + [['worker_count_change', '6']] + [['job_unavailable', nil]] * 2
      end
    end
  end

  describe "Que.wake!" do
    it "when mode = :off should do nothing" do
      Que.connection = nil
      Que.mode = :off
      Que.worker_count = 4
      sleep_until { Que::Worker.workers.all? &:sleeping? }
      Que.wake!
      sleep_until { Que::Worker.workers.all? &:sleeping? }
      $logger.messages.map{|m| JSON.load(m).values_at('event', 'value')}.should ==
        [['mode_change', 'off'], ['worker_count_change', '4']]
    end

    it "when mode = :sync should do nothing" do
      Que.connection = nil
      Que.mode = :sync
      Que.worker_count = 4
      sleep_until { Que::Worker.workers.all? &:sleeping? }
      Que.wake!
      sleep_until { Que::Worker.workers.all? &:sleeping? }
      $logger.messages.map{|m| JSON.load(m).values_at('event', 'value')}.should ==
        [['mode_change', 'sync'], ['worker_count_change', '4']]
    end

    it "when mode = :async and worker_count = 0 should do nothing" do
      Que.connection = nil
      Que.mode = :async
      Que.worker_count = 0
      sleep_until { Que::Worker.workers.all? &:sleeping? }
      Que.wake!
      sleep_until { Que::Worker.workers.all? &:sleeping? }
      $logger.messages.map{|m| JSON.load(m).values_at('event', 'value')}.should ==
        [['mode_change', 'async'], ['worker_count_change', '0']]
    end

    it "when mode = :async and worker_count > 0 should wake up a single worker" do
      Que.mode = :async
      Que.worker_count = 4
      sleep_until { Que::Worker.workers.all? &:sleeping? }

      BlockJob.enqueue
      Que.wake!

      $q1.pop
      Que::Worker.workers.first.should be_working
      Que::Worker.workers[1..3].each { |w| w.should be_sleeping }
      DB[:que_jobs].count.should be 1
      $q2.push nil

      sleep_until { Que::Worker.workers.all? &:sleeping? }
      DB[:que_jobs].count.should be 0
    end

    it "when mode = :async and worker_count > 0 should be thread-safe" do
      Que.mode = :async
      Que.worker_count = 4
      sleep_until { Que::Worker.workers.all? &:sleeping? }
      threads = 4.times.map { Thread.new { 100.times { Que.wake! } } }
      threads.each(&:join)
    end
  end

  describe "Que.wake_all!" do
    it "when mode = :off should do nothing" do
      Que.connection = nil
      Que.mode = :off
      Que.worker_count = 4
      sleep_until { Que::Worker.workers.all? &:sleeping? }
      Que.wake_all!
      sleep_until { Que::Worker.workers.all? &:sleeping? }
      $logger.messages.map{|m| JSON.load(m).values_at('event', 'value')}.should ==
        [['mode_change', 'off'], ['worker_count_change', '4']]
    end

    it "when mode = :sync should do nothing" do
      Que.connection = nil
      Que.mode = :sync
      Que.worker_count = 4
      sleep_until { Que::Worker.workers.all? &:sleeping? }
      Que.wake_all!
      sleep_until { Que::Worker.workers.all? &:sleeping? }
      $logger.messages.map{|m| JSON.load(m).values_at('event', 'value')}.should ==
        [['mode_change', 'sync'], ['worker_count_change', '4']]
    end

    it "when mode = :async and worker_count = 0 should do nothing" do
      Que.connection = nil
      Que.mode = :async
      Que.worker_count = 0
      sleep_until { Que::Worker.workers.all? &:sleeping? }
      Que.wake_all!
      sleep_until { Que::Worker.workers.all? &:sleeping? }
      $logger.messages.map{|m| JSON.load(m).values_at('event', 'value')}.should ==
        [['mode_change', 'async'], ['worker_count_change', '0']]
    end

    # This spec requires at least four connections.
    it "when mode = :async and worker_count > 0 should wake up all workers" do
      Que.adapter = QUE_ADAPTERS[:pond]

      Que.mode = :async
      Que.worker_count = 4
      sleep_until { Que::Worker.workers.all? &:sleeping? }

      4.times { BlockJob.enqueue }
      Que.wake_all!
      4.times { $q1.pop }

      Que::Worker.workers.each{ |worker| worker.should be_working }
      4.times { $q2.push nil }

      sleep_until { Que::Worker.workers.all? &:sleeping? }
      DB[:que_jobs].count.should be 0
    end if QUE_ADAPTERS[:pond]

    it "when mode = :async and worker_count > 0 should be thread-safe" do
      Que.mode = :async
      Que.worker_count = 4
      sleep_until { Que::Worker.workers.all? &:sleeping? }
      threads = 4.times.map { Thread.new { 100.times { Que.wake_all! } } }
      threads.each(&:join)
    end
  end
end
