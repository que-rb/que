# frozen_string_literal: true

require 'rake'
require 'rake/testtask'

Rake::TestTask.new :test do |t|
  t.libs = ['spec']
  # Don't run any specs found in the gems that CircleCI vendors.
  t.pattern = './spec/**/*_spec.rb'
end

task default: :test
task spec:    :test
