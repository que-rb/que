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

        # When the process exits, safely interrupt any jobs that are still running.
        at_exit { Que.stop! }
      end
    end
  end
end
