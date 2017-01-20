# frozen_string_literal: true

# Travis seems to freeze the VM the tests run in sometimes, so bump up the limit
# when running in CI.
QUE_SLEEP_UNTIL_TIMEOUT = ENV['CI'] ? 10 : 2

# Helper for testing threaded code.
def sleep_until(timeout = QUE_SLEEP_UNTIL_TIMEOUT)
  deadline = Time.now + timeout
  loop do
    break if yield
    if Time.now > deadline
      puts "sleep_until timeout reached!"
      raise "sleep_until timeout reached!"
    end
    sleep 0.01
  end
end

def suppress_warnings
  original_verbosity, $VERBOSE = $VERBOSE, nil
  yield
ensure
  $VERBOSE = original_verbosity
end
