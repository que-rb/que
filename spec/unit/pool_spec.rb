require 'spec_helper'

describe "Managing the Worker pool" do
  it "should log mode changes" do
    Que.mode = :sync
    Que.mode = :off

    $logger.messages.count.should be 2
    m1, m2 = $logger.messages.map{|m| JSON.load(m)}

    m1['event'].should == 'mode_change'
    m1['value'].should == 'sync'

    m2['event'].should == 'mode_change'
    m2['value'].should == 'off'
  end

  describe "Que.mode = :sync" do
    it "should make jobs run in the same thread as they are queued" do
      Que.mode = :sync

      ArgsJob.queue(5, :testing => "synchronous").should be_an_instance_of ArgsJob
      $passed_args.should == [5, {'testing' => "synchronous"}]
      DB[:que_jobs].count.should be 0
    end

    it "should not affect jobs that are queued with specific run_ats" do
      Que.mode = :sync

      ArgsJob.queue(5, :testing => "synchronous", :run_at => Time.now + 60)
      DB[:que_jobs].select_map(:job_class).should == ["ArgsJob"]
    end
  end

  describe "Que.mode = :async" do
    it "should spin up 4 workers" do
      Que.mode = :async
      Que.worker_count.should be 4
      sleep_until { Que::Worker.workers.all?(&:sleeping?) }

      $logger.messages.map{|m| JSON.load(m).values_at('event', 'value')}.should ==
        [['mode_change', 'async'], ['worker_count_change', '4']] + [['job_unavailable', nil]] * 4
    end

    it "should be done automatically when setting a worker count" do
      Que.worker_count = 2
      Que.mode.should == :async
      Que.worker_count.should == 2
      sleep_until { Que::Worker.workers.all?(&:sleeping?) }

      $logger.messages.map{|m| JSON.load(m).values_at('event', 'value')}.should ==
        [['mode_change', 'async'], ['worker_count_change', '2']] + [['job_unavailable', nil]] * 2
    end

    it "should not affect the number of workers if a worker_count has already been set" do
      Que.worker_count = 1
      Que.mode = :async
      Que.worker_count.should be 1
      sleep_until { Que::Worker.workers.all?(&:sleeping?) }

      $logger.messages.map{|m| JSON.load(m).values_at('event', 'value')}.should ==
        [['mode_change', 'async'], ['worker_count_change', '1'], ['job_unavailable', nil]]
    end

    it "then Que.worker_count = 0 should set the mode to :off" do
      Que.mode = :async
      Que.worker_count.should be 4

      sleep_until { Que::Worker.workers.all?(&:sleeping?) }

      Que.worker_count = 0
      Que.worker_count.should == 0
      Que.mode.should == :off

      $logger.messages.map{|m| JSON.load(m).values_at('event', 'value')}.should ==
        [['mode_change', 'async'], ['worker_count_change', '4']] + [['job_unavailable', nil]] * 4 + [['mode_change', 'off'], ['worker_count_change', '0']]
    end

    it "then Que.worker_count = 2 should gracefully decrease the number of workers" do
      Que.mode = :async
      workers = Que::Worker.workers.dup
      workers.count.should be 4
      sleep_until { Que::Worker.workers.all?(&:sleeping?) }

      Que.worker_count = 2
      Que.worker_count.should be 2
      sleep_until { Que::Worker.workers.all?(&:sleeping?) }

      workers[0..1].should == Que::Worker.workers
      workers[2..3].each do |worker|
        worker.should be_an_instance_of Que::Worker
        worker.thread.status.should == false
      end

      $logger.messages.map{|m| JSON.load(m).values_at('event', 'value')}.should ==
        [['mode_change', 'async'], ['worker_count_change', '4']] + [['job_unavailable', nil]] * 4 + [['worker_count_change', '2']]
    end

    it "then Que.worker_count = 6 should gracefully increase the number of workers" do
      Que.mode = :async
      workers = Que::Worker.workers.dup
      workers.count.should be 4

      sleep_until { Que::Worker.workers.all?(&:sleeping?) }
      Que.worker_count = 6
      Que.worker_count.should be 6
      sleep_until { Que::Worker.workers.all?(&:sleeping?) }

      workers.should == Que::Worker.workers[0..3]

      $logger.messages.map{|m| JSON.load(m).values_at('event', 'value')}.should ==
        [['mode_change', 'async'], ['worker_count_change', '4']] + [['job_unavailable', nil]] * 4 + [['worker_count_change', '6']] + [['job_unavailable', nil]] * 2
    end

    it "then Que.mode = :off should gracefully shut down workers" do
      Que.mode = :async
      workers = Que::Worker.workers.dup
      workers.count.should be 4

      sleep_until { Que::Worker.workers.all?(&:sleeping?) }
      Que.mode = :off
      Que.worker_count.should be 0

      workers.count.should be 4
      workers.each { |worker| worker.thread.status.should be false }

      $logger.messages.map{|m| JSON.load(m).values_at('event', 'value')}.should ==
        [['mode_change', 'async'], ['worker_count_change', '4']] + [['job_unavailable', nil]] * 4 + [['mode_change', 'off'], ['worker_count_change', '0']]
    end

    it "then Que.wake! should wake up a single worker" do
      Que.mode = :async
      sleep_until { Que::Worker.workers.all? &:sleeping? }

      BlockJob.queue
      Que.wake!

      $q1.pop
      Que::Worker.workers.first.should be_working
      Que::Worker.workers[1..3].each { |w| w.should be_sleeping }
      DB[:que_jobs].count.should be 1
      $q2.push nil

      sleep_until { Que::Worker.workers.all? &:sleeping? }
      DB[:que_jobs].count.should be 0
    end

    it "then Que.wake! should be thread-safe" do
      Que.mode = :async
      threads = 4.times.map { Thread.new { 100.times { Que.wake! } } }
      threads.each(&:join)
    end

    it "then Que.wake_all! should wake up all workers" do
      # This spec requires at least four connections.
      Que.adapter = QUE_ADAPTERS[:connection_pool]

      Que.mode = :async
      sleep_until { Que::Worker.workers.all? &:sleeping? }

      4.times { BlockJob.queue }
      Que.wake_all!
      4.times { $q1.pop }

      Que::Worker.workers.each{ |worker| worker.should be_working }
      4.times { $q2.push nil }

      sleep_until { Que::Worker.workers.all? &:sleeping? }
      DB[:que_jobs].count.should be 0
    end if QUE_ADAPTERS[:connection_pool]

    it "then Que.wake_all! should be thread-safe" do
      Que.mode = :async
      threads = 4.times.map { Thread.new { 100.times { Que.wake_all! } } }
      threads.each(&:join)
    end

    it "should wake a worker every Que.wake_interval seconds" do
      Que.mode = :async
      sleep_until { Que::Worker.workers.all? &:sleeping? }
      Que.wake_interval = 0.01 # 10 ms
      Que::Job.queue
      sleep_until { DB[:que_jobs].count == 0 }
    end

    it "should work jobs in the queue defined by QUE_QUEUE" do
      begin
        Que::Job.queue 1
        Que::Job.queue 2, :queue => 'my_queue'

        ENV['QUE_QUEUE'] = 'my_queue'

        Que.mode = :async
        sleep_until { Que::Worker.workers.all? &:sleeping? }
        DB[:que_jobs].count.should be 1

        job = DB[:que_jobs].first
        job[:queue].should == ''
        job[:args].should == '[1]'
      ensure
        ENV.delete('QUE_QUEUE')

        if @worker
          @worker.stop
          @worker.wait_until_stopped
        end
      end
    end
  end
end
