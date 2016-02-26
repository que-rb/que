# frozen_string_literal: true

#!/usr/bin/env ruby

# Run tests a bunch of times, flush out thread race conditions /  errors.
test_runs = if ENV['TESTS']
              Integer(ENV['TESTS'])
            else
              25
            end


# I think travis might be pausing jobs, let's try a higher timeout
QUE_TEST_TIMEOUT = 10

%w( Gemfile spec/gemfiles/Gemfile1 spec/gemfiles/Gemfile2 ).each do |gemfile|
  # Install the particular gemfile
  system("BUNDLE_GEMFILE=#{gemfile} bundle")
  1.upto(test_runs) do |i|
    puts "Test Run #{i}"
    exit(-1) if !system("bundle exec rake")
  end
end
