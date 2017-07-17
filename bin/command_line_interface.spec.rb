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

  describe "when invoked without a file to require" do
    it "should infer ./config/environment.rb if it exists"

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
