# frozen_string_literal: true

require_relative 'command_line_interface'
require 'spec_helper'

describe Que::CommandLineInterface do
  VACUUM = Object.new

  $que_spec_file_number = 0

  LOADED_FILES = {}

  def next_file_name
    "file_#{$que_spec_file_number += 1}"
  end

  def VACUUM.puts(arg)
    @messages ||= []
    @messages << arg
  end

  def VACUUM.messages
    @messages ||= []
  end

  def execute(text)
    args   = text.split(/\s/)
    output = VACUUM
    Que::CommandLineInterface.parse(args: args, output: output)
  end

  let :written_files do
    []
  end

  def write_file(name)
    written_files << name

    filename = "#{name}.rb"

    dirname = File.dirname(filename)
    unless File.directory?(dirname)
      FileUtils.mkdir_p(dirname)
    end

    File.open(filename, 'w') do |file|
      file.write %(LOADED_FILES["#{name}"] = true)
    end
  end

  def assert_successful_invocation(command)
    BlockJob.enqueue
    t = Thread.new { execute(command) }

    $q1.pop

    @que_locker = DB[:que_lockers].first

    $stop_que_executable = true
    $q2.push nil

    assert_equal 0, t.value
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
    it "should infer ./config/environment.rb if it exists" do
      write_file 'config/environment'

      assert_successful_invocation ""

      assert LOADED_FILES['config/environment']
      FileUtils.rm_r("./config")
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
      files = 2.times.map { next_file_name }
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
      name = next_file_name
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
      next_file_name
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
      wait_period: 0.1
    )
      locker_starts = internal_messages(event: 'locker_start')
      assert_equal 1, locker_starts.length

      locker_start = locker_starts.first

      assert_equal true, locker_start[:listen]
      assert_equal ['default'], locker_start[:queues]
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

    it "with a configurable list of queues"

    it "with a configurable local queue size"

    it "with a configurable log level"
  end
end
