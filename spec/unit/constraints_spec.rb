# frozen_string_literal: true

require 'spec_helper'

describe Que do
  def assert_constraint_error(name, &block)
    e = assert_raises(Sequel::CheckConstraintViolation, &block)
    assert_includes e.message, "violates check constraint \"#{name}\""
  end

  describe "table constraints" do
    it "should make sure that a job has valid arguments" do
      assert_constraint_error 'data_format' do
        DB[:que_jobs].
          insert(job_class: 'Que::Job', data: JSON.dump({}))
      end

      assert_constraint_error 'data_format' do
        DB[:que_jobs].
          insert(job_class: 'Que::Job', data: JSON.dump({args: 4}))
      end
    end
  end
end
