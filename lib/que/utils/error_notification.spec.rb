# frozen_string_literal: true

require 'spec_helper'

describe Que::Utils::ErrorNotification do
  describe "notify_error" do
    it "should pass the args to the error notification proc" do
      passed = nil
      Que.error_notifier = proc { |*args| passed = args; :blah }

      assert_equal :blah, Que.notify_error(1)
      assert_equal [1], passed

      assert_equal :blah, Que.notify_error(1, 2, 3)
      assert_equal [1, 2, 3], passed
    end

    it "when there is no error notification proc should do nothing" do
      Que.error_notifier = nil
      assert_nil Que.notify_error(1)
    end

    describe "when the error_notifier isn't a callable" do
      it "should log loudly and swallow the error" do
        Que.error_notifier = Object.new
        assert_nil Que.notify_error(1)

        assert_equal 1, logged_messages.length
        m = logged_messages.first

        assert_equal "error_notifier callable raised an error", m[:message]
        assert_match(/undefined method/, m[:error_message])
        assert_instance_of Array, m[:error_backtrace]
      end
    end

    describe "when the error notification proc raises an error" do
      it "should log loudly and swallow it" do
        Que.error_notifier = proc { |*args| raise "Uh-oh!" }
        assert_nil Que.notify_error(1)

        assert_equal 1, logged_messages.length
        m = logged_messages.first

        assert_equal "error_notifier callable raised an error", m[:message]
        assert_equal "Uh-oh!", m[:error_message]
        assert_instance_of Array, m[:error_backtrace]
      end
    end

    describe "when the error notification callable is a lambda" do
      it "with a specific argument count should only pass the appropriate number of arguments" do
        passed = nil

        Que.error_notifier = -> (a) { passed = [a]; nil }
        assert_nil Que.notify_error(1, 2)
        assert_equal [1], passed
        assert_nil Que.notify_error(3, 4, 5)
        assert_equal [3], passed

        Que.error_notifier = -> (a, b) { passed = [a, b]; nil }
        assert_nil Que.notify_error(1, 2)
        assert_equal [1, 2], passed
        assert_nil Que.notify_error(3, 4, 5)
        assert_equal [3, 4], passed
      end

      it "with a variable argument count should pass everything" do
        passed = nil

        Que.error_notifier = -> (*args) { passed = args; nil }
        assert_nil Que.notify_error(1, 2)
        assert_equal [1, 2], passed
        assert_nil Que.notify_error(3, 4, 5)
        assert_equal [3, 4, 5], passed
      end
    end
  end

  describe "notify_error_async" do
    it "should invoke notify_error in a separate thread" do
      passed = nil
      Que.error_notifier = proc { |*args| passed = args }

      assert_equal true, Que.notify_error_async(1, 2)
      sleep_until_equal([1, 2]) { passed }
      assert_empty Que::Utils::ErrorNotification::ASYNC_QUEUE
    end

    it "should swallow the error if there are more than five in the queue" do
      begin
        passed = nil
        q = Queue.new
        Que.error_notifier = proc { |*args| passed = args; q.pop }

        assert_equal true, Que.notify_error_async(1, 2)
        sleep_until_equal([1, 2]) { passed }

        assert_equal 0, Que::Utils::ErrorNotification::ASYNC_QUEUE.size

        5.times { |i| assert_equal true, Que.notify_error_async(i) }

        assert_equal 5, Que::Utils::ErrorNotification::ASYNC_QUEUE.size

        assert_equal false, Que.notify_error_async('blah')
      ensure
        Que.error_notifier = nil
        q.push(nil)
        sleep_until_equal(0) do
          Que::Utils::ErrorNotification::ASYNC_QUEUE.size
        end
      end
    end
  end
end
