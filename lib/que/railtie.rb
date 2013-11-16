module Que
  class Railtie < Rails::Railtie
    config.que = Que
    config.que.connection = ::ActiveRecord if defined?(::ActiveRecord)

    rake_tasks do
      load 'que/rake_tasks.rb'
    end
  end
end
