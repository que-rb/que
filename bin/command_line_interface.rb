# frozen_string_literal: true

require 'optparse'
require 'ostruct'

module Que
  module CommandLineInterface
    class << self
      def parse(args:, output:)
        options = OpenStruct.new
        results = {}

        OptionParser.new do |opts|
          opts.banner = 'usage: que [options] file/to/require ...'

          opts.on('-w', '--worker-count [COUNT]', Integer, "Set number of workers in process (default: 4)") do |worker_count|
            options.worker_count = worker_count
          end

          opts.on('-i', '--wake-interval [INTERVAL]', Float, "Set maximum interval between polls of the job queue (in seconds) (default: 0.1)") do |wake_interval|
            options.wake_interval = wake_interval
          end

          opts.on('-l', '--log-level [LEVEL]', String, "Set level of Que's logger (debug, info, warn, error, fatal) (default: info)") do |log_level|
            options.log_level = log_level
          end

          opts.on('-q', '--queue-name [NAME]', String, "Set the name of the queue to work jobs from (default: the default queue)") do |queue_name|
            options.queue_name = queue_name
          end

          opts.on('-v', '--version', "Show Que version") do
            require 'que'
            output.puts "Que version #{Que::VERSION}"
            results[:should_exit] = true
          end

          opts.on('-h', '--help', "Show help text") do
            output.puts opts
            results[:should_exit] = true
          end
        end.parse!(args)

        results
      end
    end
  end
end
