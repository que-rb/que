# frozen_string_literal: true

module Que
  VERSION = '2.0.0.beta1'

  def self.job_schema_version
    2
  end

  def self.supported_job_schema_versions
    if RUBY_VERSION.start_with?("2")
      [1, 2]
    else
      [2]
    end
  end
end
