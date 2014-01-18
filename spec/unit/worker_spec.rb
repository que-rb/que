require 'spec_helper'

describe Que::Worker do
  before do
    @job_queue    = Que::JobQueue.new
    @result_queue = Que::ResultQueue.new

    @worker = Que::Worker.new :job_queue    => @job_queue,
                              :result_queue => @result_queue
  end

  def run_jobs(*jobs)
    {} while @result_queue.shift # Clear result queue.
    jobs = jobs.flatten
    job_ids = jobs.map { |j| j[:job_id].to_i }
    @job_queue.push(jobs)
    sleep_until { @result_queue.to_a.sort == job_ids.sort }
  end

  it "should repeatedly work jobs that are passed to it via its job_queue, ordered correctly" do
    begin
      $results = []

      class WorkerJob < Que::Job
        def run(number)
          $results << number
        end
      end

      [1, 2, 3].each { |i| WorkerJob.queue i, :priority => i }
      job_ids = DB[:que_jobs].order_by(:priority).select_map(:job_id)
      run_jobs Que.execute("SELECT * FROM que_jobs").shuffle

      $results.should == [1, 2, 3]
      @result_queue.to_a.should == job_ids
    ensure
      $results = nil
    end
  end

  it "should pass a job's arguments to the run method and delete it from the database" do
    ArgsJob.queue 1, 'two', {'three' => 3}
    DB[:que_jobs].count.should be 1

    run_jobs Que.execute("SELECT * FROM que_jobs").first

    DB[:que_jobs].count.should be 0
    $passed_args.should == [1, 'two', {'three' => 3}]
  end

  it "should make it easy to destroy the job within the same transaction as other changes" do
    class DestroyJob < Que::Job
      def run
        destroy
      end
    end

    DestroyJob.queue
    DB[:que_jobs].count.should be 1

    run_jobs Que.execute("SELECT * FROM que_jobs").first
    DB[:que_jobs].count.should be 0
  end

  it "should make a job's argument hashes indifferently accessible" do
    DB[:que_jobs].count.should be 0
    ArgsJob.queue 1, 'two', {'array' => [{'number' => 3}]}
    DB[:que_jobs].count.should be 1

    run_jobs Que.execute("SELECT * FROM que_jobs").first
    $passed_args.last[:array].first[:number].should == 3
  end

  describe "when an error is raised" do
    it "should not crash the worker" do
      ErrorJob.queue :priority => 1
      Que::Job.queue :priority => 2

      job_ids = DB[:que_jobs].order_by(:priority).select_map(:job_id)
      run_jobs Que.execute("SELECT * FROM que_jobs")
      @result_queue.to_a.should == job_ids
    end

    it "should pass it to the error handler" do
      begin
        error = nil
        Que.error_handler = proc { |e| error = e }

        ErrorJob.queue :priority => 1

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

        ErrorJob.queue :priority => 1
        Que::Job.queue :priority => 2

        run_jobs Que.execute("SELECT * FROM que_jobs")
      ensure
        Que.error_handler = nil
      end
    end

    it "should exponentially back off the job" do
      ErrorJob.queue

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

      RetryIntervalJob.queue

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

      RetryIntervalFormulaJob.queue

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
  end
end
