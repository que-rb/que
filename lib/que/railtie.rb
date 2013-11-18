module Que
  class Railtie < Rails::Railtie
    config.que = Que
    config.que.connection = ::ActiveRecord if defined?(::ActiveRecord)

    rake_tasks do
      load 'que/rake_tasks.rb'
    end

    initializer "que.setup" do
      ActiveSupport.on_load(:active_record) do
        Que.logger ||= Rails.logger
        Que.mode ||= Rails.env.test? ? :sync : :async
      end
    end
  end
end
