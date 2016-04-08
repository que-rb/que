# frozen_string_literal: true

module Que
  class Railtie < Rails::Railtie
    config.que = Que

    Que.logger         = proc { Rails.logger }
    Que.mode           = :sync if Rails.env.test?
    Que.connection     = ::ActiveRecord if defined? ::ActiveRecord
    Que.json_converter = :with_indifferent_access.to_proc

    rake_tasks do
      load 'que/rake_tasks.rb'
    end
  end
end
