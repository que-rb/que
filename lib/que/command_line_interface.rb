# frozen_string_literal: true

require 'optparse'
require 'logger'
require 'uri'

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

        options                = {}
        queues                 = []
        log_level              = 'info'
        log_internals          = false
        poll_interval          = 5
        poll_interval_variance = 0
        connection_url         = nil
        worker_count           = nil
        worker_priorities      = nil

        parser =
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
              '-j',
              '--poll-interval-variance [INTERVAL]',
              Float,
              "Set maximum variance in poll interval, in seconds (default: 0)",
            ) do |j|
              poll_interval_variance = j.to_f
            end

            opts.on(
              '--listen [LISTEN]',
              String,
              "Set to false to disable listen mode (default: true)"
            ) do |listen|
              options[:listen] = listen != "false"
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
              '-p',
              '--worker-priorities [LIST]',
              Array,
              "List of priorities to assign to workers (default: 10,30,50,any,any,any)",
            ) do |priority_array|
              worker_priorities =
                priority_array.map do |p|
                  case p
                  when /\Aany\z/i
                    nil
                  when /\A\d+\z/
                    Integer(p)
                  else
                    output.puts "Invalid priority option: '#{p}'. Please use an integer or the word 'any'."
                    return 1
                  end
                end
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
              '-w',
              '--worker-count [COUNT]',
              Integer,
              "Set number of workers in process (default: 6)",
            ) do |w|
              worker_count = w
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
              '--connection-url [URL]',
              String,
              "Set a custom database url to connect to for locking purposes.",
            ) do |url|
              options[:connection_url] = url
            end

            opts.on(
              '--log-internals',
              "Log verbosely about Que's internal state. " \
                "Only recommended for debugging issues",
            ) do |l|
              log_internals = true
            end

            opts.on(
              '--maximum-buffer-size [SIZE]',
              Integer,
              "Set maximum number of jobs to be locked and held in this " \
                "process awaiting a worker (default: 8)",
            ) do |s|
              options[:maximum_buffer_size] = s
            end

            opts.on(
              '--minimum-buffer-size [SIZE]',
              Integer,
              "Unused (deprecated)",
            ) do |s|
              warn "The --minimum-buffer-size SIZE option has been deprecated and will be removed in v2.0 (it's actually been unused since v1.0.0.beta4)"
            end

            opts.on(
              '--wait-period [PERIOD]',
              Float,
              "Set maximum interval between checks of the in-memory job queue, " \
                "in milliseconds (default: 50)",
            ) do |p|
              options[:wait_period] = p
            end

            opts.on(
              '--pidfile [PATH]',
              String,
              "Write the PID of this process to the specified file.",
              ) do |p|
              options[:pidfile] = File.expand_path(p)
            end
          end

        parser.parse!(args)

        options[:worker_priorities] =
          if worker_count && worker_priorities
            worker_priorities.values_at(0...worker_count)
          elsif worker_priorities
            worker_priorities
          elsif worker_count
            Array.new(worker_count) { nil }
          else
            [10, 30, 50, nil, nil, nil]
          end

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
          rescue LoadError => e
            output.puts "Could not load file '#{file}': #{e}"
            return 1
          end
        end

        Que.logger ||= Logger.new(STDOUT)

        if log_internals
          Que.internal_logger = Que.logger
        end

        begin
          Que.get_logger.level = Logger.const_get(log_level.upcase)
        rescue NameError
          output.puts "Unsupported logging level: #{log_level} (try debug, info, warn, error, or fatal)"
          return 1
        end

        if queues.any?
          queues_hash = {}

          queues.each do |queue|
            name, interval = queue.split('=')
            p              = interval ? Float(interval) : poll_interval

            Que.assert(p > 0.01) { "Poll intervals can't be less than 0.01 seconds!" }

            queues_hash[name] = p
          end

          options[:queues] = queues_hash
        end

        options[:poll_interval]          = poll_interval
        options[:poll_interval_variance] = poll_interval_variance

        locker =
          begin
            Que::Locker.new(**options)
          rescue => e
            output.puts(e.message)
            return 1
          end

        # It's a bit sloppy to use a global for this when a local variable would
        # do, but we want to stop the locker from the CLI specs, so...
        $stop_que_executable = false
        %w[INT TERM].each { |signal| trap(signal) { $stop_que_executable = true } }

        output.puts(
          <<~STARTUP
            Que #{Que::VERSION} started worker process with:
              Worker threads: #{locker.workers.length} (priorities: #{locker.workers.map { |w| w.priority || 'any' }.join(', ')})
              Buffer size: #{locker.job_buffer.maximum_size}
              Queues:
            #{locker.queues.map { |queue, interval| "    - #{queue} (poll interval: #{interval}s)" }.join("\n")}
            Que waiting for jobs...
          STARTUP
        )

        loop do
          sleep 0.01
          break if $stop_que_executable || locker.stopping?
        end

        output.puts "\nFinishing Que's current jobs before exiting..."

        locker.stop!

        output.puts "Que's jobs finished, exiting..."
        return 0
      end
    end
  end
end
