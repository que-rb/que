# frozen_string_literal: true

require 'optparse'

module Que
  module CommandLineInterface
    # Have a sensible default require file for Rails.
    RAILS_ENVIRONMENT_FILE = './config/environment.rb'

    class << self
      # Need to rely on dependency injection a bit to make this method cleanly
      # testable :/
      def parse(
        args:,
        output:,
        default_require_file: RAILS_ENVIRONMENT_FILE
      )

        queues             = []
        log_level          = 'info'
        wait_period        = 100
        worker_count       = 6
        poll_interval      = 5
        log_internals      = false
        minimum_queue_size = 2
        maximum_queue_size = 8
        worker_priorities  = [10, 30, 50]

        OptionParser.new do |opts|
          opts.banner = 'usage: que [options] [file/to/require] ...'

          opts.on(
            '-h',
            '--help',
            "Show this help text.",
          ) do
            output.puts opts.help
            return 0
          end

          opts.on(
            '-i',
            '--poll-interval [INTERVAL]',
            Float,
            "Set maximum interval between polls for available jobs, " \
              "in seconds (default: 5)",
          ) do |i|
            poll_interval = i
          end

          opts.on(
            '-l',
            '--log-level [LEVEL]',
            String,
            "Set level at which to log to STDOUT " \
              "(debug, info, warn, error, fatal) (default: info)",
          ) do |l|
            log_level = l
          end

          opts.on(
            '-q',
            '--queue-name [NAME]',
            String,
            "Set a queue name to work jobs from. " \
              "Can be passed multiple times. " \
              "(default: the default queue only)",
          ) do |queue_name|
            queues << queue_name
          end

          opts.on(
            '-v',
            '--version',
            "Print Que version and exit.",
          ) do
            require 'que'
            output.puts "Que version #{Que::VERSION}"
            return 0
          end

          opts.on(
            '-w',
            '--worker-count [COUNT]',
            Integer,
            "Set number of workers in process (default: 6)",
          ) do |w|
            worker_count = w
          end

          opts.on(
            '--log-internals',
            Integer,
            "Log verbosely about Que's internal state. " \
              "Only recommended for debugging issues",
          ) do |l|
            log_internals = true
          end

          opts.on(
            '--maximum-queue-size [SIZE]',
            Integer,
            "Set maximum number of jobs to be cached in this process " \
              "awaiting a worker (default: 8)",
          ) do |s|
            maximum_queue_size = s
          end

          opts.on(
            '--minimum-queue-size [SIZE]',
            Integer,
            "Set minimum number of jobs to be cached in this process " \
              "awaiting a worker (default: 2)",
          ) do |s|
            minimum_queue_size = s
          end

          opts.on(
            '--wait-period [PERIOD]',
            Float,
            "Set maximum interval between checks of the in-memory job queue, " \
              "in milliseconds (default: 100)",
          ) do |p|
            wait_period = p
          end

          opts.on(
            '--worker-priorities [LIST]',
            Array,
            "List of priorities to assign to workers, " \
              "unspecified workers take jobs of any priority (default: 10,30,50)",
          ) do |p|
            worker_priorities = p.map(&:to_i)
          end
        end.parse!(args)

        if args.length.zero?
          if File.exist?(default_require_file)
            args << default_require_file
          else
            output.puts <<-OUTPUT
You didn't include any Ruby files to require!
Que needs to be able to load your application before it can process jobs.
(Or use `que -h` for a list of options)
OUTPUT
            return 1
          end
        end

        args.each do |file|
          begin
            require file
          rescue LoadError
            output.puts "Could not load file '#{file}'"
            return 1
          end
        end

        $stop_que_executable = false
        %w[INT TERM].each { |signal| trap(signal) { $stop_que_executable = true } }

        Que.logger ||= Logger.new(STDOUT)

        if log_internals
          Que.internal_logger = Que.logger
        end

        begin
          Que.logger.level = Logger.const_get(log_level.upcase)
        rescue NameError
          output.puts "Unsupported logging level: #{log_level} (try debug, info, warn, error, or fatal)"
          return 1
        end

        if minimum_queue_size > maximum_queue_size
          output.puts "Your minimum-queue-size (#{minimum_queue_size}) is " \
            "greater than your maximum-queue-size (#{maximum_queue_size})!"
          return 1
        end

        options = {
          wait_period:        wait_period.to_f / 1000, # Milliseconds to seconds.
          worker_count:       worker_count,
          poll_interval:      poll_interval,
          minimum_queue_size: minimum_queue_size,
          maximum_queue_size: maximum_queue_size,
          worker_priorities:  worker_priorities,
        }

        options[:queues] = queues if queues.any?

        locker = Que::Locker.new(options)

        loop do
          sleep 0.01
          break if $stop_que_executable
        end

        output.puts ''
        output.puts "Finishing Que's current jobs before exiting..."

        locker.stop!

        output.puts "Que's jobs finished, exiting..."
        return 0
      end
    end
  end
end
