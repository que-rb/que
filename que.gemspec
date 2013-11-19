# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'que/version'

Gem::Specification.new do |spec|
  spec.name          = 'que'
  spec.version       = Que::Version
  spec.authors       = ["Chris Hanks"]
  spec.email         = ['christopher.m.hanks@gmail.com']
  spec.description   = %q{A job queue that uses PostgreSQL's advisory locks for speed and reliability.}
  spec.summary       = %q{A PostgreSQL-based Job Queue}
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

  spec.add_dependency 'sequel'
  spec.add_dependency 'activerecord'
  spec.add_dependency 'pg'
  spec.add_dependency 'connection_pool'
  spec.add_dependency 'multi_json', '~> 1.0'
end
