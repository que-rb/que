# frozen_string_literal: true

require 'spec_helper'

if defined?(::ActiveRecord)
  describe Que::ActiveRecord::Connection do
    it "should use Rails.application.executor.wrap, if it exists, when checking out connections" do
      # This is a hacky spec, but it's better than requiring Rails.
      called = false
      rails, application, executor = 3.times.map { Object.new }

      executor.define_singleton_method(:wrap) do |&block|
        called = true
        block.call
      end

      application.define_singleton_method(:executor) { executor }
      rails.define_singleton_method(:application) { application }

      refute defined?(::Rails)
      ::Rails = rails

      Que.connection = ::ActiveRecord

      assert_equal false, called
      Que.checkout {}
      assert_equal true, called

      Object.send :remove_const, :Rails
      refute defined?(::Rails)
    end
  end

  describe Que::ActiveRecord::Connection::JobMiddleware do
    before do
      Que.connection = ::ActiveRecord

      class SecondDatabaseModel < ActiveRecord::Base
        establish_connection(QUE_URL)
      end

      if ::ActiveRecord.version >= Gem::Version.new('7.1')
        SecondDatabaseModel.connection_handler.clear_active_connections!(:all)
      else
        SecondDatabaseModel.clear_active_connections!
      end
      refute SecondDatabaseModel.connection_handler.active_connections?

      class SecondDatabaseModelJob < Que::Job
        def run(*args)
          SecondDatabaseModel.connection.execute("SELECT 1")
        end
      end
    end

    it "should clear connections to secondary DBs between jobs" do
      SecondDatabaseModelJob.run

      refute SecondDatabaseModel.connection_handler.active_connections?
    end


    it "shouldn't clear connections to secondary DBs between jobs if run_synchronously is enabled " do
      Que::Job.run_synchronously = true
      SecondDatabaseModelJob.run

      assert SecondDatabaseModel.connection_handler.active_connections?
    end
  end
end
