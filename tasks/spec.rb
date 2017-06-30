# frozen_string_literal: true

require 'rake'
require 'rake/testtask'

Rake::TestTask.new :test do |t|
  t.libs = ['spec']
  t.pattern = '*/**/*.*spec.rb'
end

task default: :test
task spec:    :test
