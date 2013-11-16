# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'que/version'

Gem::Specification.new do |spec|
  spec.name          = 'que'
  spec.version       = Que::Version
  spec.authors       = ["Chris Hanks"]
  spec.email         = ['christopher.m.hanks@gmail.com']
  spec.description   = %q{Durable job queueing with PostgreSQL.}
  spec.summary       = %q{Durable, efficient job queueing with PostgreSQL.}
  spec.homepage      = 'https://github.com/chanks/que'
  spec.license       = 'MIT'

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler', '~> 1.3'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rspec', '~> 2.14.1'
  spec.add_development_dependency 'pry'

  spec.add_development_dependency 'sequel'
  spec.add_development_dependency 'activerecord'
  spec.add_development_dependency 'pg'
  spec.add_development_dependency 'connection_pool'
end
