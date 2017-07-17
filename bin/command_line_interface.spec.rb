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

  around do |&block|
    super() do
      VACUUM.messages.clear

      block.call

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
      code = execute("")
      assert_equal 0, code
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

      code = execute "./#{files[0]} ./#{files[1]}"
      assert_equal 0, code
      assert_empty VACUUM.messages

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
      super
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
