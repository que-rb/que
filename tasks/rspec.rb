# frozen_string_literal: true

require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new :default do |spec|
  spec.pattern = './spec/**/*_spec.rb'
end

# Shortcut to skip the adapter specs, and run only with the basic PG
# connection. I use this occasionally to make sure ActiveRecord isn't loaded,
# so any accidental Rails-isms are caught.
RSpec::Core::RakeTask.new :pg do |spec|
  spec.pattern = './spec/unit/*_spec.rb'
end
