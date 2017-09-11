# frozen_string_literal: true

require_relative 'command_line_interface'
require 'spec_helper'

describe Que::CommandLineInterface do
  LOADED_FILES = {}

  around do |&block|
    super() do
      # Let the CLI set the logger if it needs to.
      Que.logger = nil

      block.call

      $stop_que_executable = nil
      LOADED_FILES.clear
      written_files.each { |name| File.delete("#{name}.rb") }
    end
  end

  let(:written_files) { [] }

  let :output do
    o = Object.new

    def o.puts(arg)
      messages << arg
    end

    def o.messages
      @messages ||= []
    end

    o
  end

  def assert_successful_invocation(
    command,
    queue_name: 'default',
    default_require_file: Que::CommandLineInterface::RAILS_ENVIRONMENT_FILE
  )

    BlockJob.enqueue(queue: queue_name)

    thread =
      Thread.new do
        execute(
          command,
          default_require_file: default_require_file,
        )
      end

    unless sleep_until { !$q1.empty? }
      puts "CLI invocation thread hung!"
      thread.join
    end

    $q1.pop

    @que_locker = DB[:que_lockers].first

    yield if block_given?

    $stop_que_executable = true
    $q2.push nil

    assert_equal 0, thread.value
  end

  def execute(
    text,
    default_require_file: Que::CommandLineInterface::RAILS_ENVIRONMENT_FILE
  )
    Que::CommandLineInterface.parse(
      args: text.split(/\s/),
      output: output,
      default_require_file: default_require_file,
    )
  end

  def write_file
    # On CircleCI we run the spec suite in parallel, and writing/deleting the
    # same files will result in spec failures. So instead just generate a new
    # file name for each spec to write/delete.

    name = "spec/temp/file_#{Digest::MD5.hexdigest(rand.to_s)}"
    written_files << name
    File.open("#{name}.rb", 'w') { |f| f.puts %(LOADED_FILES["#{name}"] = true) }
    name
  end

  ["-h", "--help"].each do |command|
    it "when invoked with #{command} should print help text" do
      code = execute(command)
      assert_equal 0, code
      assert_equal 1, output.messages.length
      assert_match %r(usage: que \[options\] \[file/to/require\]), output.messages.first.to_s
    end
  end

  ["-v", "--version"].each do |command|
    it "when invoked with #{command} should print the version" do
      code = execute(command)
      assert_equal 0, code
      assert_equal 1, output.messages.length
      assert_equal "Que version #{Que::VERSION}", output.messages.first.to_s
    end
  end

  describe "when requiring files" do
    it "should infer the default require file if it exists" do
      filename = write_file

      assert_successful_invocation "", default_require_file: "./#{filename}.rb"

      assert_equal(
        {filename => true},
        LOADED_FILES
      )
    end

    it "should output an error message if no files are specified and the rails config file doesn't exist" do
      code = execute("")
      assert_equal 1, code
      assert_equal 1, output.messages.length
      assert_equal <<-MSG, output.messages.first.to_s
You didn't include any Ruby files to require!
Que needs to be able to load your application before it can process jobs.
(Or use `que -h` for a list of options)
MSG
    end

    it "should be able to require multiple files" do
      files = 2.times.map { write_file }

      assert_successful_invocation "./#{files[0]} ./#{files[1]}"

      assert_equal(
        [
          "",
          "Finishing Que's current jobs before exiting...",
          "Que's jobs finished, exiting...",
        ],
        output.messages,
      )

      assert_equal(
        {
          files[0] => true,
          files[1] => true,
        },
        LOADED_FILES,
      )
    end

    it "should raise an error if any of the files don't exist" do
      name = write_file
      code = execute "./#{name} ./nonexistent_file"
      assert_equal 1, code

      assert_equal ["Could not load file './nonexistent_file'"], output.messages

      assert_equal(
        {name => true},
        LOADED_FILES
      )
    end
  end

  describe "should start up a locker" do
    let(:filename) { write_file }

    before { filename }

    after do
      assert_equal(
        {filename => true},
        LOADED_FILES
      )
    end

    def assert_locker_instantiated(
      worker_priorities: [10, 30, 50],
      poll_interval: 5,
      wait_period: 50,
      queues: ['default'],
      minimum_queue_size: 2,
      maximum_queue_size: 8
    )

      locker_instantiates = internal_messages(event: 'locker_instantiate')
      assert_equal 1, locker_instantiates.length

      locker_instantiate = locker_instantiates.first

      assert_equal true,               locker_instantiate[:listen]
      assert_equal true,               locker_instantiate[:poll]
      assert_equal queues,             locker_instantiate[:queues]
      assert_equal poll_interval,      locker_instantiate[:poll_interval]
      assert_equal wait_period,        locker_instantiate[:wait_period]
      assert_equal minimum_queue_size, locker_instantiate[:minimum_queue_size]
      assert_equal maximum_queue_size, locker_instantiate[:maximum_queue_size]
      assert_equal worker_priorities,  locker_instantiate[:worker_priorities]
    end

    def assert_locker_started(
      worker_priorities: [10, 30, 50, nil, nil, nil]
    )

      locker_starts = internal_messages(event: 'locker_start')
      assert_equal 1, locker_starts.length

      locker_start = locker_starts.first

      assert_equal worker_priorities, locker_start[:worker_priorities]
      assert_equal @que_locker[:pid], locker_start[:backend_pid]
    end

    it "that can shut down gracefully" do
      assert_successful_invocation "./#{filename}"
      assert_locker_started
    end

    ["-w", "--worker-count"].each do |command|
      it "with #{command} to configure the worker count" do
        assert_successful_invocation "./#{filename} #{command} 10"
        assert_locker_instantiated
        assert_locker_started(
          worker_priorities: [10, 30, 50, nil, nil, nil, nil, nil, nil, nil],
        )
      end
    end

    ["-i", "--poll-interval"].each do |command|
      it "with #{command} to configure the poll interval" do
        assert_successful_invocation "./#{filename} #{command} 10"
        assert_locker_instantiated(poll_interval: 10)
        assert_locker_started
      end
    end

    it "with --wait-period to configure the wait period" do
      assert_successful_invocation "./#{filename} --wait-period 200"
      assert_locker_instantiated(
        wait_period: 200,
      )
    end

    ["-q", "--queue-name"].each do |command|
      it "with #{command} to configure the queue being worked" do
        assert_successful_invocation "./#{filename} #{command} my_queue", queue_name: 'my_queue'
        assert_locker_instantiated(
          queues: {my_queue: 5}
        )
      end
    end

    it "should support using multiple arguments to specify multiple queues" do
      queues = ['queue_1', 'queue_2', 'queue_3', 'queue_4']

      assert_successful_invocation \
        "./#{filename} -q queue_1 --queue-name queue_2 -q queue_3 --queue-name queue_4",
        queue_name: queues.sample # Shouldn't matter.

      assert_locker_instantiated(
        queues: {queue_1: 5, queue_2: 5, queue_3: 5, queue_4: 5}
      )
    end

    it "should support specifying poll intervals for individual queues" do
      assert_successful_invocation \
        "./#{filename} --poll-interval 4 -q queue_1=6 --queue-name queue_2 -q queue_3 --queue-name queue_4=7",
        queue_name: 'queue_3'

      assert_locker_instantiated(
        queues: {queue_1: 6, queue_2: 4, queue_3: 4, queue_4: 7},
        poll_interval: 4,
      )

      poller_instantiations = internal_messages(event: 'poller_instantiate')

      assert_equal(
        [["queue_1", 6.0], ["queue_2", 4.0], ["queue_3", 4.0], ["queue_4", 7.0]],
        poller_instantiations.map{|p| p.values_at(:queue, :poll_interval)}
      )
    end

    it "with a configurable local queue size" do
      assert_successful_invocation \
        "./#{filename} --minimum-queue-size 8 --maximum-queue-size 20"

      assert_locker_instantiated(
        minimum_queue_size: 8,
        maximum_queue_size: 20,
      )
    end

    it "should raise an error if the minimum_queue_size is above the maximum_queue_size" do
      code = execute("./#{filename} --minimum-queue-size 10")
      assert_equal 1, code
      assert_equal 1, output.messages.length
      assert_equal \
        "minimum queue size (10) is greater than the maximum queue size (8)!",
        output.messages.first.to_s
    end

    it "with a configurable log level" do
      assert_successful_invocation("./#{filename} --log-level=warn") do
        logger = Que.logger
        assert_instance_of Logger, logger
        assert_equal logger.level, Logger::WARN
      end
    end

    it "when passing a nonexistent log level should raise an error" do
      code = execute("./#{filename} --log-level=warning")
      assert_equal 1, code
      assert_equal 1, output.messages.length
      assert_equal \
        "Unsupported logging level: warning (try debug, info, warn, error, or fatal)",
        output.messages.first.to_s
    end

    describe "--connection-url" do
      it "should specify a database url for the locker" do
        assert_successful_invocation("./#{filename} --connection-url postgres://postgres:@localhost/que-test") do
          refute_includes DEFAULT_QUE_POOL.instance_variable_get(:@checked_out), @que_locker[:pid]
        end
      end

      it "when omitted should use a connection from the connection pool" do
        assert_successful_invocation("./#{filename}") do
          assert_includes DEFAULT_QUE_POOL.instance_variable_get(:@checked_out), @que_locker[:pid]
        end
      end
    end

    it "when passing --log-internals should output Que's internal logs" do
      Que.internal_logger = nil

      assert_successful_invocation("./#{filename} --log-internals --log-level=warn") do
        logger = Que.logger
        assert_instance_of Logger, logger
        assert_equal logger.level, Logger::WARN

        assert_equal logger.object_id, Que.internal_logger.object_id
      end
    end

    it "when passing --worker-priorities to specify worker priorities" do
      assert_successful_invocation("./#{filename} --worker-priorities 10,15,20,25")

      assert_locker_started(
        worker_priorities: [10, 15, 20, 25, nil, nil],
      )
    end
  end
end
