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

namespace :test do
  desc "Run tests in parallel (alias: \`rake p\`)"
  task :parallel do
    ENV['PARALLELIZE_TESTS'] = 'true'
    ENV['N'] ||= '4'
    Rake::Task[:test].invoke
  end
end

task p: :'test:parallel'
