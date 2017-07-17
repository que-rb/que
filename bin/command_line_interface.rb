# frozen_string_literal: true

require 'optparse'

module Que
  module CommandLineInterface
    class << self
      def parse(args:, output:)
        options = {}

        # Queues
        # poll_interval:      Que::Locker::DEFAULT_POLL_INTERVAL,
        # wait_period:        Que::Locker::DEFAULT_WAIT_PERIOD,
        # minimum_queue_size: Que::Locker::DEFAULT_MINIMUM_QUEUE_SIZE,
        # maximum_queue_size: Que::Locker::DEFAULT_MAXIMUM_QUEUE_SIZE,
        # worker_priorities:  [10, 30, 50, nil, nil, nil]

        # Defaults:
        options = {
          poll_interval:  5,
          worker_count:   6,
        }

        wait_period = 100
        log_level = :info
        queues = []

        OptionParser.new do |opts|
          opts.banner = 'usage: que [options] [file/to/require] ...'

          opts.on(
            '-w',
            '--worker-count [COUNT]',
            Integer,
            "Set number of workers in process (default: 6)",
          ) do |w|
            options[:worker_count] = worker_count
          end

          opts.on(
            '-p',
            '--poll-interval [INTERVAL]',
            Float,
            "Set maximum interval between polls for available jobs " \
              "(in seconds) (default: 5)",
          ) do |p|
            options[:poll_interval] = wake_interval
          end

          opts.on(
            '-p',
            '--wait-period [PERIOD]',
            Float,
            "Set maximum interval between checks of the in-memory job queue " \
              "(in milliseconds) (default: 100)",
          ) do |p|
            wait_period = p
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
              "Can be included multiple times. " \
              "Defaults to only the default queue.",
          ) do |queue_name|
            queues << queue_name
          end

          opts.on(
            '-v',
            '--version',
            "Show Que version",
          ) do
            require 'que'
            output.puts "Que version #{Que::VERSION}"
            return 0
          end

          opts.on(
            '-h',
            '--help',
            "Show help text",
          ) do
            output.puts opts.help
            return 0
          end
        end.parse!(args)

        options[:queues] = queues if queues.any?

        # Convert from milliseconds to seconds.
        options[:wait_period] = wait_period.to_f / 1000

        if args.length.zero?
          # Sensible default for Rails.
          if File.exist?('./config/environment.rb')
            args << './config/environment.rb'
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

        return 0

        # $stop_que_executable = false
        # %w[INT TERM].each { |signal| trap(signal) { $stop_que_executable = true } }

        # loop do
        #   sleep 0.01
        #   break if $stop_que_executable
        # end


        # Que.logger ||= Logger.new(STDOUT)

        # begin
        #   if log_level = (options.log_level || ENV['QUE_LOG_LEVEL'])
        #     Que.logger.level = Logger.const_get(log_level.upcase)
        #   end
        # rescue NameError
        #   $stdout.puts "Bad logging level: #{log_level}"
        #   exit 1
        # end

        # Que.queue_name    = options.queue_name     || ENV['QUE_QUEUE']         || Que.queue_name    || nil
        # Que.worker_count  = (options.worker_count  || ENV['QUE_WORKER_COUNT']  || Que.worker_count  || 4).to_i
        # Que.wake_interval = (options.wake_interval || ENV['QUE_WAKE_INTERVAL'] || Que.wake_interval || 0.1).to_f
        # Que.mode          = :async

        # stop = false
        # %w(INT TERM).each { |signal| trap(signal) { stop = true } }

        # loop do
        #   sleep 0.01
        #   break if stop
        # end

        # $stdout.puts
        # $stdout.puts "Finishing Que's current jobs before exiting..."
        # Que.worker_count = 0
        # Que.mode = :off
        # $stdout.puts "Que's jobs finished, exiting..."

      end
    end
  end
end
