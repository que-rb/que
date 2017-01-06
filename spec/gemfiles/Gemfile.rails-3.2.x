source 'https://rubygems.org'

gem 'que', path: '../..'

group :development, :test do
  gem 'rake', '< 11.0'

  gem 'activerecord',    '~> 3.2.0', :require => nil
  gem 'sequel',          :require => nil
  gem 'connection_pool', :require => nil
  gem 'pg',              :require => nil, :platform => :ruby
  gem 'pg_jruby',        :require => nil, :platform => :jruby
end

group :test do
  gem 'rspec', '~> 2.14.1'
  gem 'pry'
end
