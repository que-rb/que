# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'que/version'

Gem::Specification.new do |spec|
  spec.name          = 'que'
  spec.version       = Que::VERSION
  spec.authors       = ["Chris Hanks"]
  spec.email         = ['christopher.m.hanks@gmail.com']
  spec.description   = %q{A job queue that uses PostgreSQL's advisory locks for speed and reliability.}
  spec.summary       = %q{A PostgreSQL-based Job Queue}
  spec.homepage      = 'https://github.com/chanks/que'
  spec.license       = 'MIT'

  files_to_exclude = [
    /\A\.circleci/,
    /\AGemfile/,
    /\Aspec/,
    /\Atasks/,
    /spec\.rb\z/,
  ]

  spec.files = `git ls-files`.split($/).reject do |file|
    files_to_exclude.any? { |r| r === file }
  end

  spec.executables   = ['que']
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler'
end
