require 'bundler/gem_tasks'

require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new :default do |spec|
  spec.pattern = './spec/**/*_spec.rb'
end

# Shortcut to run only the pg specs. I use this occasionally to make sure
# ActiveRecord isn't loaded, and so any accidental Rails-isms are caught.
RSpec::Core::RakeTask.new :pg do |spec|
  spec.pattern = './spec/adapters/pg_spec.rb'
end
