# frozen_string_literal: true

require 'spec_helper'

if defined?(::ActiveRecord)
  describe Que::Rails::ActiveRecord do
    it "should use Rails.application.executor, if it exists, when checking out connections"

    it "should clear connections to secondary DBs between jobs" # do
    #   class SecondDatabaseModel < ActiveRecord::Base
    #     establish_connection(QUE_URL)
    #   end

    #   SecondDatabaseModel.clear_active_connections!
    #   SecondDatabaseModel.connection_handler.active_connections?.should == false

    #   class SecondDatabaseModelJob < Que::Job
    #     def run(*args)
    #       SecondDatabaseModel.connection.execute("SELECT 1")
    #     end
    #   end

    #   SecondDatabaseModelJob.enqueue
    #   Que::Job.work

    #   SecondDatabaseModel.connection_handler.active_connections?.should == false
    # end
  end
end
