# frozen_string_literal: true

class DummyLogger
  attr_reader :messages, :messages_with_levels

  def initialize
    @messages = []
    @messages_with_levels = []
  end

  [:debug, :info, :warn, :error, :fatal, :unknown].each do |level|
    define_method level do |message|
      messages << message
      messages_with_levels << [message, level]
    end
  end

  def reset
    messages.clear
    messages_with_levels.clear
  end
end
