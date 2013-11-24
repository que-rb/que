source 'https://rubygems.org'

group :development, :test do
  gem 'rake'

  gem 'activerecord',    :require => nil
  gem 'sequel',          :require => nil
  gem 'connection_pool', :require => nil

  gem 'pg',            :platform => :ruby,  :require => nil
  gem 'jdbc-postgres', :platform => :jruby, :require => nil
end

group :test do
  gem 'rspec', '~> 2.14.1'
  gem 'pry'
end

gemspec
