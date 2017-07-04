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

    describe "when the error notification proc raises an error" do
      it "should log loudly and swallow it" do
        Que.error_notifier = proc { |*args| raise "Uh-oh!" }
        assert_nil Que.notify_error(1)

        assert_equal 1, logged_messages.length
        m = logged_messages.first

        assert_equal "error_notifier callable raised an error", m['message']
        assert_equal "Uh-oh!", m['error_message']
        assert_instance_of Array, m['error_backtrace']
      end
    end
  end

  describe "notify_error_async" do
    it "should invoke notify_error in a separate thread"

    it "should swallow the error if there are more than five in the queue"
  end

  describe "error_notifier=" do
    it "should raise an error unless passed nil or a callable"
  end
end
