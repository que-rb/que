# Helper for testing threaded code.
def sleep_until(timeout = 2)
  deadline = Time.now + timeout
  loop do
    break if yield
    raise "Thing never happened!" if Time.now > deadline
    sleep 0.01
  end
end
