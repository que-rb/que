#!/usr/bin/env ruby

# Run tests a bunch of times, flush out thread race conditions /  errors.
test_runs = if ENV['TESTS']
              Integer(ENV['TESTS'])
            else
              50
            end

1.upto(test_runs) do |i|
  puts "Test Run #{i}"
  exit(-1) if !system("bundle exec rake")
end
