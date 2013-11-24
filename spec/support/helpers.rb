require 'uri'

# Helper for testing threaded code.
def sleep_until(timeout = 2)
  deadline = Time.now + timeout
  loop do
    break if yield
    raise "Thing never happened!" if Time.now > deadline
    sleep 0.01
  end
end

def jruby?
  defined?(RUBY_ENGINE) && RUBY_ENGINE == 'jruby'
end

# Sequel takes raw jdbc urls, so we need to convert something like
# "postgres://postgres:@localhost/que-test" to
# "jdbc:postgresql://localhost/que-test?user=postgres"
# Keeping this stupidly simple for now.
def convert_url_to_jdbc(url)
  uri = URI.parse(url)
  "jdbc:postgresql://#{uri.host}#{uri.path}?user=#{uri.user}"
end
