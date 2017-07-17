# frozen_string_literal: true

require_relative 'command_line_interface'
require 'spec_helper'

describe Que::CommandLineInterface do
  VACUUM = Object.new

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
      file.write "$#{name.tr('/', '_')}_required = true"
    end
  end

  before do
    VACUUM.messages.clear
  end

  after do
    written_files.each do |file|
      File.delete("#{file}.rb")
      eval "$#{name.tr('/', '_')}_required = nil"
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
      code = execute("")
      assert_equal 0, code
      assert $config_environment_required
    end

    it "should output an error message if the rails config file doesn't exist" do
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
      write_file 'file_1'
      write_file 'file_2'

      code = execute "./file_1 ./file_2"
      assert_equal 0, code
      assert_empty VACUUM.messages

      assert $file_1_required
      assert $file_2_required
    end

    it "should raise an error if any of the files don't exist" do
      write_file 'file_1'
      code = execute "./file_1 ./file_2"
      assert_equal 1, code

      assert_empty VACUUM.messages

      assert $file_1_required
      refute $file_2_required
    end
  end

  describe "should start up a locker" do
    before do
      write_file 'config/environment'
    end

    after do
      assert $config_environment_required
    end

    it "that can shut down gracefully"

    it "with a configurable worker count and priorities"

    it "with a configurable list of queues"

    it "with a configurable wait period"

    it "should error if the wait period is below a minimum"

    it "with a configurable local queue size"

    it "with a configurable poll interval"

    it "should error if the poll interval is below a minimum"

    it "with a configurable log level"
  end
end
