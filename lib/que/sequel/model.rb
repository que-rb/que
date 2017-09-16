# frozen_string_literal: true

module Que
  module Sequel
    class Model < ::Sequel::Model(:que_jobs)
      dataset_module do
        conditions = {
          errored:   ::Sequel.identifier(:error_count) > 0,
          expired:   ::Sequel.~(expired_at: nil),
          finished:  ::Sequel.~(finished_at: nil),
          scheduled: ::Sequel.identifier(:run_at) > ::Sequel::CURRENT_TIMESTAMP,
        }

        conditions.each do |name, condition|
          subset           name,  condition
          subset :"not_#{name}", ~condition
        end

        subset :ready,     conditions.values.map(&:~).inject{|a, b| a & b}
        subset :not_ready, conditions.values.         inject{|a, b| a | b}
      end
    end
  end
end
