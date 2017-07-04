# frozen_string_literal: true

require 'spec_helper'

describe Que::Utils::ErrorNotification do
  describe "notify_error" do
    it "should pass the args to the error notification proc"

    it "when there is no error notification proc should do nothing"

    describe "when the error notification proc raises an error" do
      it "should log loudly and swallow it"
    end

    describe "when passed an async argument" do
      it "should pass the args to a queue to be notified on a separate thread"
    end
  end

  describe "error_notifier=" do
    it "should raise an error unless passed nil or a callable"
  end
end
