# frozen_string_literal: true

require 'spec_helper'
require 'active_record'

if ActiveRecord.version.release >= Gem::Version.new('4.2')
  ActiveRecord::Base.raise_in_transactional_callbacks = true
end
ActiveRecord::Base.establish_connection(QUE_URL)

Que.connection = ActiveRecord
QUE_POOLS[:active_record] = Que.pool

describe "Que using the ActiveRecord pool" do
  before { Que.pool = QUE_POOLS[:active_record] }

  it_behaves_like "a Que pool"

  it "should use the same connection that ActiveRecord does" do
    begin
      class ActiveRecordJob < Que::Job
        def run
          $pid1 = Que.execute("SELECT pg_backend_pid()").first[:pg_backend_pid]
          $pid2 = Integer(ActiveRecord::Base.connection.select_value("SELECT pg_backend_pid()"))
        end
      end

      ActiveRecordJob.enqueue
      locker = Que::Locker.new

      sleep_until { Integer === $pid1 && Integer === $pid2 }
      $pid1.should == $pid2
    ensure
      $pid1 = $pid2 = nil
      locker.stop! if locker
    end
  end

  it "should support Rails' special extensions for times" do
    pending
    raise "Some issue with advisory locks here"

    locker = Que::Locker.new poll_interval: 0.005.seconds
    sleep 0.01

    run_at = Que::Job.enqueue(run_at: 1.minute.ago).attrs[:run_at]
    run_at.should be_within(3).of(Time.now - 60)

    sleep_until { DB[:que_jobs].empty? }
    locker.stop!
  end

  it "should be able to survive an ActiveRecord::Rollback without raising an error" do
    ActiveRecord::Base.transaction do
      Que::Job.enqueue
      raise ActiveRecord::Rollback, "Call tech support!"
    end
    DB[:que_jobs].count.should be 0
  end

  it "should be able to tell when it's in an ActiveRecord transaction" do
    Que.should_not be_in_transaction
    ActiveRecord::Base.transaction do
      Que.should be_in_transaction
    end
  end
end
