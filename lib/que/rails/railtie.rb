# frozen_string_literal: true

module Que
  module Rails
    class Railtie < ::Rails::Railtie
      config.que = Que

      Que.run_asynchronously = true if ::Rails.env.test?

      Que.logger     = proc { ::Rails.logger }
      Que.connection = ::ActiveRecord if defined? ::ActiveRecord
    end
  end
end
