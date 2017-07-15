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

  before do
    VACUUM.messages.clear
  end

  it "when invoked with -h or --help should print help text" do
    ["-h", "--help"].each do |command|
      code = execute(command)
      assert_equal 0, code
      assert_equal 1, VACUUM.messages.length
      assert_match %r(usage: que \[options\] \[file/to/require\]), VACUUM.messages.first.to_s
      VACUUM.messages.clear
    end
  end

  it "when invoked with -v or --version should print the version" do
    ["-v", "--version"].each do |command|
      code = execute(command)
      assert_equal 0, code
      assert_equal 1, VACUUM.messages.length
      assert_equal "Que Version #{Que::VERSION}", VACUUM.messages.first.to_s
      VACUUM.messages.clear
    end
  end

  describe "when invoked without a file to require" do
    it "should infer ./config/environment.rb if it exists"

    it "should output an error message if the rails config file doesn't exist"
  end

  describe "should start up a locker" do
    it "after requiring a file"

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
