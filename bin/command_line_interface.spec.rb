# frozen_string_literal: true

require_relative 'command_line_interface'
require 'spec_helper'

describe Que::CommandLineInterface do
  VACUUM = Object.new
  LOADED_FILES = {}

  # On CircleCI we run the spec suite in parallel, and writing/deleting the same
  # files will result in spec failures. So instead just generate a new file name
  # for each spec to write/delete.
  def random_filename
    "spec/temp/file_#{Digest::MD5.hexdigest(rand.to_s)}"
  end

  def VACUUM.puts(arg)
    @messages ||= []
    @messages << arg
  end

  def VACUUM.messages
    @messages ||= []
  end

  def execute(
    text,
    default_require_file: Que::CommandLineInterface::RAILS_ENVIRONMENT_FILE
  )

    args   = text.split(/\s/)
    output = VACUUM
    Que::CommandLineInterface.parse(
      args: args,
      output: output,
      default_require_file: default_require_file,
    )
  end

  let :written_files do
    []
  end

  def write_file(name)
    written_files << name

    File.open("#{name}.rb", 'w') do |file|
      file.write %(LOADED_FILES["#{name}"] = true)
    end
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

    $q1.pop

    @que_locker = DB[:que_lockers].first

    $stop_que_executable = true
    $q2.push nil

    assert_equal 0, thread.value
  end

  around do |&block|
    super() do
      VACUUM.messages.clear

      block.call

      $stop_que_executable = nil

      written_files.map do |name|
        File.delete("#{name}.rb") if File.exist?("#{name}.rb")
      end
      LOADED_FILES.clear
    end
  end

  ["-h", "--help"].each do |command|
    it "when invoked with #{command} should print help text" do
      code = execute(command)
      assert_equal 0, code
      assert_equal 1, VACUUM.messages.length
      assert_match %r(usage: que \[options\] \[file/to/require\]), VACUUM.messages.first.to_s
    end
  end

  ["-v", "--version"].each do |command|
    it "when invoked with #{command} should print the version" do
      code = execute(command)
      assert_equal 0, code
      assert_equal 1, VACUUM.messages.length
      assert_equal "Que version #{Que::VERSION}", VACUUM.messages.first.to_s
    end
  end

  describe "when requiring files" do
    it "should infer the default require file if it exists" do
      filename = random_filename
      write_file(filename)

      assert_successful_invocation "", default_require_file: "./#{filename}.rb"

      assert_equal(
        {filename => true},
        LOADED_FILES
      )
    end

    it "should output an error message if no files are specified and the rails config file doesn't exist" do
      code = execute("")
      assert_equal 1, code
      assert_equal 1, VACUUM.messages.length
      assert_equal <<-MSG, VACUUM.messages.first.to_s
You didn't include any Ruby files to require!
Que needs to be able to load your application before it can process jobs.
(Or use `que -h` for a list of options)
MSG
    end

    it "should be able to require multiple files" do
      files = 2.times.map { random_filename }
      files.each { |file| write_file(file) }

      assert_successful_invocation "./#{files[0]} ./#{files[1]}"

      assert_equal(
        [
          "",
          "Finishing Que's current jobs before exiting...",
          "Que's jobs finished, exiting...",
        ],
        VACUUM.messages,
      )

      assert_equal(
        {files[0] => true, files[1] => true},
        LOADED_FILES
      )
    end

    it "should raise an error if any of the files don't exist" do
      name = random_filename
      write_file name
      code = execute "./#{name} ./nonexistent_file"
      assert_equal 1, code

      assert_equal ["Could not load file './nonexistent_file'"], VACUUM.messages

      assert_equal(
        {name => true},
        LOADED_FILES
      )
    end
  end

  describe "should start up a locker" do
    let :file_name do
      random_filename
    end

    before do
      write_file(file_name)
    end

    after do
      assert_equal(
        {file_name => true},
        LOADED_FILES
      )
    end

    def assert_locker_started(
      worker_priorities: [10, 30, 50, nil, nil, nil],
      poll_interval: 5,
      wait_period: 0.1,
      queues: ['default']
    )
      locker_starts = internal_messages(event: 'locker_start')
      assert_equal 1, locker_starts.length

      locker_start = locker_starts.first

      assert_equal true, locker_start[:listen]
      assert_equal queues, locker_start[:queues]
      assert_equal @que_locker[:pid], locker_start[:backend_pid]
      assert_equal poll_interval, locker_start[:poll_interval]
      assert_equal wait_period, locker_start[:wait_period]
      assert_equal 2, locker_start[:minimum_queue_size]
      assert_equal 8, locker_start[:maximum_queue_size]
      assert_equal worker_priorities, locker_start[:worker_priorities]
    end

    it "that can shut down gracefully" do
      assert_successful_invocation "./#{file_name}"
      assert_locker_started
    end

    ["-w", "--worker-count"].each do |command|
      it "with #{command} to configure the worker count" do
        assert_successful_invocation "./#{file_name} #{command} 10"
        assert_locker_started(
          worker_priorities: [10, 30, 50, nil, nil, nil, nil, nil, nil, nil],
        )
      end
    end

    ["-i", "--poll-interval"].each do |command|
      it "with #{command} to configure the poll interval" do
        assert_successful_invocation "./#{file_name} #{command} 10"
        assert_locker_started(
          poll_interval: 10,
        )
      end
    end

    it "should error if the poll interval is below a minimum"

    ["-p", "--wait-period"].each do |command|
      it "with #{command} to configure the wait period" do
        assert_successful_invocation "./#{file_name} #{command} 200"
        assert_locker_started(
          wait_period: 0.2,
        )
      end
    end

    it "should error if the wait period is below a minimum"

    ["-q", "--queue-name"].each do |command|
      it "with #{command} to configure the queue being worked" do
        assert_successful_invocation "./#{file_name} #{command} my_queue", queue_name: 'my_queue'
        assert_locker_started(
          queues: ['my_queue']
        )
      end
    end

    it "should support using multiple arguments to specify multiple queues" do
      assert_successful_invocation "./#{file_name} -q queue_1 --queue-name queue_2 -q queue_3 --queue-name queue_4", queue_name: 'queue_3'
      assert_locker_started(
        queues: ['queue_1', 'queue_2', 'queue_3', 'queue_4']
      )
    end

    it "with a configurable local queue size"

    it "with a configurable log level"
  end
end
