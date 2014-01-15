# Helper for testing threaded code.
QUE_TEST_TIMEOUT ||= 2
def sleep_until(timeout = ENV['QUE_TEST_TIMEOUT'] || 2)
  deadline = Time.now + timeout
  loop do
    break if yield
    raise "Thing never happened!" if Time.now > deadline
    sleep 0.01
  end
end
