source 'https://rubygems.org'

group :development, :test do
  gem 'rake', '< 11.0'

  gem 'activerecord',    require: nil
  gem 'sequel',          require: nil
  gem 'connection_pool', require: nil
  gem 'pond',            require: nil

  gem 'pg',       require: nil, platform: :ruby
  gem 'pg_jruby', require: nil, platform: :jruby
end

group :test do
  gem 'minitest', '~> 5.10.1'
  gem 'm'
  gem 'pry'
  gem 'pg_examiner'
end

platforms :rbx do
  gem 'rubysl', '~> 2.0'
  gem 'json', '~> 1.8'
end

gemspec
