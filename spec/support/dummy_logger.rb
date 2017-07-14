# frozen_string_literal: true

class DummyLogger
  attr_reader :messages

  def initialize
    @mutex    = Mutex.new
    @messages = []
  end

  [:debug, :info, :warn, :error, :fatal, :unknown].each do |level|
    define_method level do |thing|
      messages << thing
    end
  end
end
