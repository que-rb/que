module Que
  class Railtie < Rails::Railtie
    config.que = Que

    Que.logger         = proc { Rails.logger }
    Que.mode           = :sync if Rails.env.test?
    Que.connection     = ::ActiveRecord if defined? ::ActiveRecord
    Que.json_converter = proc(&:with_indifferent_access)

    rake_tasks do
      load 'que/rake_tasks.rb'
    end
  end
end
