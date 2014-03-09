# Helper for testing threaded code.
QUE_TEST_TIMEOUT ||= 2
def sleep_until(timeout = QUE_TEST_TIMEOUT)
  deadline = Time.now + timeout
  loop do
    break if yield
    raise "Thing never happened!" if Time.now > deadline
    sleep 0.01
  end
end

def suppress_warnings
  original_verbosity, $VERBOSE = $VERBOSE, nil
  yield
ensure
  $VERBOSE = original_verbosity
end
