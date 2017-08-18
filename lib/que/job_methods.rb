# frozen_string_literal: true

module Que
  module JobMethods
    def _run(args: nil)
      if args.nil?
        args = que_target.que_attrs.fetch(:data).fetch(:args)
      end

      run(*args)
    end

    # Run the job with the error handling and cleaning up that we need when
    # running in a worker. This method is skipped when running synchronously.
    def _run_asynchronously(args: nil)
      _run(args: args)
      default_finish_action unless que_target.que_resolved
    rescue => error
      que_target.que_error = error

      run_error_notifier =
        begin
          handle_error(error)
        rescue => error_2
          Que.notify_error(error_2, que_target.que_attrs)
          retry_in_default_interval
        end

      Que.notify_error(error, que_target.que_attrs) if run_error_notifier
      default_finish_action unless que_target.que_resolved
    end

    private

    def resolve_que_setting(*args)
      que_target.class.resolve_que_setting(*args)
    end

    def default_finish_action
      finish
    end

    def finish
      if id = que_target.que_attrs[:id]
        Que.execute :finish_job, [id]
      end

      que_target.que_resolved = true
    end

    def error_count
      count = que_target.que_attrs.fetch(:error_count)
      que_target.que_error ? count + 1 : count
    end

    # To be overridden in subclasses.
    def handle_error(error)
      retry_in_default_interval
    end

    def retry_in_default_interval
      retry_in(resolve_que_setting(:retry_interval, error_count))
    end

    # Explicitly check for the job id in these helpers, because it won't exist
    # if we're doing JobClass.run().
    def retry_in(period)
      if id = que_target.que_attrs[:id]
        values = [period]

        if e = que_target.que_error
          values << e.message << e.backtrace.join("\n")
        else
          values << nil << nil
        end

        Que.execute :set_error, values << id
      end

      que_target.que_resolved = true
    end

    def destroy
      if id = que_target.que_attrs[:id]
        Que.execute :destroy_job, [id]
      end

      que_target.que_resolved = true
    end
  end
end
