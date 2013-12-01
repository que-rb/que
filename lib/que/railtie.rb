module Que
  class Railtie < Rails::Railtie
    config.que = Que
    config.que.connection = ::ActiveRecord if defined?(::ActiveRecord)
    config.que.mode = :sync if Rails.env.test?

    rake_tasks do
      load 'que/rake_tasks.rb'
    end

    initializer 'que.setup' do
      ActiveSupport.on_load :after_initialize do
        Que.logger ||= Rails.logger

        # Only start up the worker pool if running as a server.
        Que.mode ||= :async if defined? Rails::Server
      end
    end
  end
end
