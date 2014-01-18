require 'spec_helper'

describe Que::Worker do
  before do
    @job_queue    = Que::JobQueue.new
    @result_queue = Que::ResultQueue.new

    @worker = Que::Worker.new :job_queue    => @job_queue,
                              :result_queue => @result_queue
  end

  def run_jobs(*jobs)
    jobs = jobs.flatten
    job_ids = jobs.map { |j| j.attrs[:job_id] }
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

      jobs = [1, 2, 3].map do |i|
        WorkerJob.new :priority => i,
                      :run_at   => Time.now,
                      :job_id   => i,
                      :args     => "[#{i}]"
      end

      run_jobs jobs.shuffle

      $results.should == [1, 2, 3]
      @result_queue.to_a.should == [1, 2, 3]
    ensure
      $results = nil
    end
  end

  it "should pass a job's arguments to the run method and delete it from the database" do
    ArgsJob.queue 1, 'two', {'three' => 3}
    DB[:que_jobs].count.should be 1

    run_jobs ArgsJob.new(Que.execute("SELECT * FROM que_jobs").first)

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

    run_jobs DestroyJob.new(Que.execute("SELECT * FROM que_jobs").first)
    DB[:que_jobs].count.should be 0
  end

  it "should make a job's argument hashes indifferently accessible" do
    DB[:que_jobs].count.should be 0
    ArgsJob.queue 1, 'two', {'array' => [{'number' => 3}]}
    DB[:que_jobs].count.should be 1

    run_jobs ArgsJob.new(Que.execute("SELECT * FROM que_jobs").first)
    $passed_args.last[:array].first[:number].should == 3
  end

  describe "when an error is raised" do
    it "should not crash the worker" do
      job_1 = ErrorJob.new :priority => 1,
                           :run_at   => Time.now,
                           :job_id   => 1,
                           :args     => '[]'

      job_2 = Que::Job.new :priority => 2,
                           :run_at   => Time.now,
                           :job_id   => 2,
                           :args     => '[]'

      run_jobs job_1, job_2
      @result_queue.to_a.should == [1, 2]
    end

    it "should pass it to the error handler" do
      begin
        error = nil
        Que.error_handler = proc { |e| error = e }

        job = ErrorJob.new :priority => 1,
                           :run_at   => Time.now,
                           :job_id   => 1,
                           :args     => '[]'

        run_jobs job
      ensure
        error.should be_an_instance_of RuntimeError
        error.message.should == "ErrorJob!"

        Que.error_handler = nil
      end
    end

    it "should not crash the worker if the error handler is problematic" do
      begin
        Que.error_handler = proc { |e| raise "Error handler error!" }

        job_1 = ErrorJob.new :priority => 1,
                             :run_at   => Time.now,
                             :job_id   => 1,
                             :args     => '[]'

        job_2 = Que::Job.new :priority => 2,
                             :run_at   => Time.now,
                             :job_id   => 2,
                             :args     => '[]'

        run_jobs [job_1, job_2].shuffle
      ensure
        Que.error_handler = nil
      end
    end

    it "should exponentially back off the job" do
      ErrorJob.queue

      run_jobs ErrorJob.new(Que.execute("SELECT * FROM que_jobs").first)

      DB[:que_jobs].count.should be 1
      job = DB[:que_jobs].first
      job[:error_count].should be 1
      job[:last_error].should =~ /\AErrorJob!\n/
      job[:run_at].should be_within(3).of Time.now + 4

      DB[:que_jobs].update :error_count => 5,
                           :run_at      => Time.now - 60

      run_jobs ErrorJob.new(Que.execute("SELECT * FROM que_jobs").first)

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

      run_jobs RetryIntervalJob.new(Que.execute("SELECT * FROM que_jobs").first)

      DB[:que_jobs].count.should be 1
      job = DB[:que_jobs].first
      job[:error_count].should be 1
      job[:last_error].should =~ /\AErrorJob!\n/
      job[:run_at].should be_within(3).of Time.now + 5

      DB[:que_jobs].update :error_count => 5,
                           :run_at      => Time.now - 60

      run_jobs RetryIntervalJob.new(Que.execute("SELECT * FROM que_jobs").first)

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

      run_jobs RetryIntervalFormulaJob.new(Que.execute("SELECT * FROM que_jobs").first)

      DB[:que_jobs].count.should be 1
      job = DB[:que_jobs].first
      job[:error_count].should be 1
      job[:last_error].should =~ /\AErrorJob!\n/
      job[:run_at].should be_within(3).of Time.now + 10

      DB[:que_jobs].update :error_count => 5,
                           :run_at      => Time.now - 60

      run_jobs RetryIntervalFormulaJob.new(Que.execute("SELECT * FROM que_jobs").first)

      DB[:que_jobs].count.should be 1
      job = DB[:que_jobs].first
      job[:error_count].should be 6
      job[:last_error].should =~ /\AErrorJob!\n/
      job[:run_at].should be_within(3).of Time.now + 60
    end
  end
end
