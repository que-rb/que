# frozen_string_literal: true

require_relative 'command_line_interface'
require 'spec_helper'

describe Que::CommandLineInterface do
  VACUUM = Object.new

  def VACUUM.puts(*args)
    @messages ||= []
    @messages << args
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
    results = execute "-h"
    assert_equal({should_exit: true}, results)
    binding.pry unless $stop
    0
  end
end
