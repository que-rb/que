# When adding/changing anything in this file, remember to update the alternate
# Gemfiles in spec/gemfiles as well!

source 'https://rubygems.org'

group :development, :test do
  gem 'rake'

  gem 'activerecord',    '~> 7.1.0', require: nil
  gem 'activejob',       '~> 7.1.0', require: nil
  gem 'sequel',          require: nil
  gem 'connection_pool', require: nil
  gem 'pond',            require: nil

  gem 'pg',       require: nil, platform: :ruby
  gem 'jruby-pg', require: nil, platform: :jruby
end

group :test do
  gem 'minitest',         '~> 5.10.1'
  gem 'minitest-profile', '0.0.2'
  gem 'minitest-hooks',   '1.4.0'
  gem 'minitest-fail-fast', '0.1.0'

  gem 'm'

  gem 'pry'
  gem 'pg_examiner', '~> 0.5.2'

  gem 'timecop', '~> 0.9.10'
end

gemspec
