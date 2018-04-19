# frozen_string_literal: true

module Que
  module Rails
    class Railtie < ::Rails::Railtie
      config.que = Que

      Que.logger     = proc { ::Rails.logger }
      Que.connection = ::ActiveRecord if defined? ::ActiveRecord
    end
  end
end
