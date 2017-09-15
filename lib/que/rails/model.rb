# frozen_string_literal: true

module Que
  module ActiveRecord
    class Model < ::ActiveRecord::Base
      self.table_name = :que_jobs
    end
  end
end
