module Que
  class Job
    attr_reader :attrs

    def initialize(attrs)
      @attrs = attrs
    end

    # Subclasses should define their own run methods, but keep an empty one
    # here so that Que::Job.enqueue can queue an empty job in testing.
    def run(*args)
    end

    def _run
      run *attrs[:args]
      destroy unless @destroyed
    end

    private

    def destroy
      Que.execute :destroy_job, attrs.values_at(:queue, :priority, :run_at, :job_id)
      @destroyed = true
    end

    @retry_interval = proc { |count| count ** 4 + 3 }

    class << self
      attr_reader :retry_interval

      def enqueue(*args)
        if args.last.is_a?(Hash)
          options   = args.pop
          queue     = options.delete(:queue) || '' if options.key?(:queue)
          job_class = options.delete(:job_class)
          run_at    = options.delete(:run_at)
          priority  = options.delete(:priority)
          args << options if options.any?
        end

        attrs = {:job_class => job_class || to_s, :args => args}

        warn "@default_run_at in #{to_s} has been deprecated and will be removed in Que version 1.0.0. Please use @run_at instead." if @default_run_at

        if t = run_at || @run_at && @run_at.call || @default_run_at && @default_run_at.call
          attrs[:run_at] = t
        end

        warn "@default_priority in #{to_s} has been deprecated and will be removed in Que version 1.0.0. Please use @priority instead." if @default_priority

        if p = priority || @priority || @default_priority
          attrs[:priority] = p
        end

        if q = queue || @queue
          attrs[:queue] = q
        end

        if Que.mode == :sync && !t
          run(*attrs[:args])
        else
          values = Que.execute(:insert_job, attrs.values_at(:queue, :priority, :run_at, :job_class, :args)).first
          new(values)
        end
      end

      def queue(*args)
        warn "#{to_s}.queue(*args) is deprecated and will be removed in Que version 1.0.0. Please use #{to_s}.enqueue(*args) instead."
        enqueue(*args)
      end

      def run(*args)
        new(:args => args).tap(&:_run)
      end

      def class_for(string)
        string.split('::').inject(Object, &:const_get)
      end
    end
  end
end
