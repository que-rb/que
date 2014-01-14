module Que
  class Railtie < Rails::Railtie
    config.que = Que

    Que.mode       = :sync if Rails.env.test?
    Que.connection = ::ActiveRecord if defined? ::ActiveRecord

    rake_tasks do
      load 'que/rake_tasks.rb'
    end

    initializer 'que.setup' do
      ActiveSupport.on_load :after_initialize do
        Que.logger ||= Rails.logger

        # Only start up the worker pool if running as a server.
        Que.mode ||= :async if defined? Rails::Server

        at_exit do
          if Que.mode == :async
            $stdout.puts "Finishing Que's current jobs before exiting..."
            Que.mode = :off
            $stdout.puts "Que's jobs finished, exiting..."
          end
        end
      end
    end
  end
end
