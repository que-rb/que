require 'spec_helper'

describe Que::Worker do
  before do
    @job_queue    = Que::JobQueue.new :maximum_size => 20
    @result_queue = Que::JobQueue.new

    @worker = Que::Worker.new :job_queue    => @job_queue,
                              :result_queue => @result_queue,
                              :queue_name   => ''
  end

  def run_jobs(*jobs)
    @result_queue.clear
    jobs = jobs.flatten.map { |job| job.values_at(:queue, :priority, :run_at, :job_id) }
    @job_queue.push *jobs
    sleep_until { @result_queue.to_a.sort == jobs.sort }
  end

  it "should repeatedly work jobs that are passed to it via its job_queue, ordered correctly" do
    begin
      $results = []

      class WorkerJob < Que::Job
        def run(number)
          $results << number
        end
      end

      [1, 2, 3].each { |i| WorkerJob.enqueue i, :priority => i }
      job_ids = DB[:que_jobs].order_by(:priority).select_map(:job_id)
      run_jobs Que.execute("SELECT * FROM que_jobs").shuffle

      $results.should == [1, 2, 3]
      @result_queue.to_a.map{|pk| pk[-1]}.should == job_ids

      events = logged_messages.select{|m| m['event'] == 'job_worked'}
      events.count.should be 3
      events.map{|m| m['job']['priority']}.should == [1, 2, 3]
    ensure
      $results = nil
    end
  end

  it "should pass a job's arguments to the run method and delete it from the database" do
    ArgsJob.enqueue 1, 'two', {'three' => 3}
    DB[:que_jobs].count.should be 1

    run_jobs Que.execute("SELECT * FROM que_jobs").first

    DB[:que_jobs].count.should be 0
    $passed_args.should == [1, 'two', {:three => 3}]
  end

  it "should make it easy to destroy the job within the same transaction as other changes" do
    class DestroyJob < Que::Job
      def run
        destroy
      end
    end

    DestroyJob.enqueue
    DB[:que_jobs].count.should be 1

    run_jobs Que.execute("SELECT * FROM que_jobs").first
    DB[:que_jobs].count.should be 0
  end

  it "should handle subclasses of other jobs" do
    begin
      class SubClassJob < Que::Job
        @priority = 2

        def run
          $job_spec_result << :sub
        end
      end

      class SubSubClassJob < SubClassJob
        @priority = 4

        def run
          super
          $job_spec_result << :subsub
        end
      end

      $job_spec_result = []
      SubClassJob.enqueue
      DB[:que_jobs].select_map(:priority).should == [2]
      run_jobs Que.execute("SELECT * FROM que_jobs").first
      $job_spec_result.should == [:sub]

      $job_spec_result = []
      SubSubClassJob.enqueue
      DB[:que_jobs].select_map(:priority).should == [4]
      run_jobs Que.execute("SELECT * FROM que_jobs").first
      $job_spec_result.should == [:sub, :subsub]
    ensure
      $job_spec_result = nil
    end
  end

  it "should handle namespaced subclasses" do
    begin
      $run = false

      module ModuleJobModule
        class ModuleJob < Que::Job
          def run
            $run = true
          end
        end
      end

      ModuleJobModule::ModuleJob.enqueue
      DB[:que_jobs].get(:job_class).should == "ModuleJobModule::ModuleJob"

      run_jobs Que.execute("SELECT * FROM que_jobs").first
      $run.should be true
    ensure
      $run = nil
    end
  end

  it "should make a job's argument hashes indifferently accessible" do
    DB[:que_jobs].count.should be 0
    ArgsJob.enqueue 1, 'two', {'array' => [{'number' => 3}]}
    DB[:que_jobs].count.should be 1

    run_jobs Que.execute("SELECT * FROM que_jobs").first
    $passed_args.last[:array].first[:number].should == 3
  end

  it "should skip a job without incident if passed the pk for a job that doesn't exist" do
    DB[:que_jobs].count.should be 0
    run_jobs :queue    => '',
             :priority => 1,
             :run_at   => Time.now,
             :job_id   => 587648

    @result_queue.to_a.map{|pk| pk[-1]}.should == [587648]
  end

  it "should only take jobs that meet its priority requirement" do
    @worker.priority = 10

    jobs = (1..20).map { |i| ['', i, Time.now, i] }

    @job_queue.push *jobs

    sleep_until { @result_queue.to_a.map{|pk| pk[-1]} == (1..10).to_a }

    @job_queue.to_a.should == jobs[10..19]
  end

  describe "when an error is raised" do
    it "should not crash the worker" do
      ErrorJob.enqueue :priority => 1
      Que::Job.enqueue :priority => 2

      job_ids = DB[:que_jobs].order_by(:priority).select_map(:job_id)
      run_jobs Que.execute("SELECT * FROM que_jobs")
      @result_queue.to_a.map{|pk| pk[-1]}.should == job_ids

      events = logged_messages.select{|m| m['event'] == 'job_errored'}
      events.count.should be 1
      event = events.first
      event['pk'][1].should == 1
      event['job']['job_id'].should be_an_instance_of Fixnum
      event['error']['class'].should == 'RuntimeError'
      event['error']['message'].should == 'ErrorJob!'
    end

    it "should pass it to the error handler" do
      begin
        error = nil
        Que.error_handler = proc { |e| error = e }

        ErrorJob.enqueue :priority => 1

        run_jobs Que.execute("SELECT * FROM que_jobs")

        error.should be_an_instance_of RuntimeError
        error.message.should == "ErrorJob!"
      ensure
        Que.error_handler = nil
      end
    end

    it "should not crash the worker if the error handler is problematic" do
      begin
        Que.error_handler = proc { |e| raise "Error handler error!" }

        ErrorJob.enqueue :priority => 1
        Que::Job.enqueue :priority => 2

        run_jobs Que.execute("SELECT * FROM que_jobs")
      ensure
        Que.error_handler = nil
      end
    end

    it "should exponentially back off the job" do
      ErrorJob.enqueue

      run_jobs Que.execute("SELECT * FROM que_jobs")

      DB[:que_jobs].count.should be 1
      job = DB[:que_jobs].first
      job[:error_count].should be 1
      job[:last_error].should =~ /\AErrorJob!\n/
      job[:run_at].should be_within(3).of Time.now + 4

      DB[:que_jobs].update :error_count => 5,
                           :run_at      => Time.now - 60

      run_jobs Que.execute("SELECT * FROM que_jobs")

      DB[:que_jobs].count.should be 1
      job = DB[:que_jobs].first
      job[:error_count].should be 6
      job[:last_error].should =~ /\AErrorJob!\n/
      job[:run_at].should be_within(3).of Time.now + 1299
    end

    it "should respect a custom retry interval" do
      class RetryIntervalJob < ErrorJob
        @retry_interval = 5
      end

      RetryIntervalJob.enqueue

      run_jobs Que.execute("SELECT * FROM que_jobs")

      DB[:que_jobs].count.should be 1
      job = DB[:que_jobs].first
      job[:error_count].should be 1
      job[:last_error].should =~ /\AErrorJob!\n/
      job[:run_at].should be_within(3).of Time.now + 5

      DB[:que_jobs].update :error_count => 5,
                           :run_at      => Time.now - 60

      run_jobs Que.execute("SELECT * FROM que_jobs")

      DB[:que_jobs].count.should be 1
      job = DB[:que_jobs].first
      job[:error_count].should be 6
      job[:last_error].should =~ /\AErrorJob!\n/
      job[:run_at].should be_within(3).of Time.now + 5
    end

    it "should respect a custom retry interval formula" do
      class RetryIntervalFormulaJob < ErrorJob
        @retry_interval = proc { |count| count * 10 }
      end

      RetryIntervalFormulaJob.enqueue

      run_jobs Que.execute("SELECT * FROM que_jobs")

      DB[:que_jobs].count.should be 1
      job = DB[:que_jobs].first
      job[:error_count].should be 1
      job[:last_error].should =~ /\AErrorJob!\n/
      job[:run_at].should be_within(3).of Time.now + 10

      DB[:que_jobs].update :error_count => 5,
                           :run_at      => Time.now - 60

      run_jobs Que.execute("SELECT * FROM que_jobs")

      DB[:que_jobs].count.should be 1
      job = DB[:que_jobs].first
      job[:error_count].should be 6
      job[:last_error].should =~ /\AErrorJob!\n/
      job[:run_at].should be_within(3).of Time.now + 60
    end

    it "should throw an error properly if there's no corresponding job class" do
      DB[:que_jobs].insert :job_class => "NonexistentClass"

      run_jobs Que.execute("SELECT * FROM que_jobs")

      DB[:que_jobs].count.should be 1
      job = DB[:que_jobs].first
      job[:error_count].should be 1
      job[:last_error].should =~ /uninitialized constant:? NonexistentClass/
      job[:run_at].should be_within(3).of Time.now + 4
    end

    it "should throw an error properly if the corresponding job class doesn't descend from Que::Job" do
      class J
        def run(*args)
        end
      end

      Que.enqueue :job_class => "J"

      run_jobs Que.execute("SELECT * FROM que_jobs")

      DB[:que_jobs].count.should be 1
      job = DB[:que_jobs].first
      job[:error_count].should be 1
      job[:run_at].should be_within(3).of Time.now + 4
    end
  end
end
