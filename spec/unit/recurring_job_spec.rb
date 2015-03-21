require 'spec_helper'

describe Que::RecurringJob do
  it "should allow for easy recurring jobs" do
    pending

    begin
      class CronJob < Que::Job
        # Default repetition interval in seconds. Can be overridden in
        # subclasses. Can use 1.minute if using Rails.
        INTERVAL = 60

        attr_reader :start_at, :end_at, :run_again_at, :time_range

        def _run
          args = attrs[:args].first
          @start_at, @end_at = Time.at(args.delete('start_at')), Time.at(args.delete('end_at'))
          @run_again_at = @end_at + self.class::INTERVAL
          @time_range = @start_at...@end_at

          super

          args['start_at'] = @end_at.to_f
          args['end_at']   = @run_again_at.to_f
          self.class.enqueue(args, run_at: @run_again_at)
        end
      end

      class MyCronJob < CronJob
        INTERVAL = 1.5

        def run(args)
          $args       = args.dup
          $time_range = time_range
        end
      end

      t = (Time.now - 1000).to_f.round(6)
      MyCronJob.enqueue :start_at => t, :end_at => t + 1.5, :arg => 4

      $args.should be nil
      $time_range.should be nil

      locker = Que::Locker.new
      sleep_until { DB[:que_jobs].get(:run_at).to_f > t }
      DB[:que_jobs].get(:run_at).to_f.should be_within(0.000001).of(t + 1.5)
      locker.stop

      $args.should == {'arg' => 4}
      $time_range.begin.to_f.round(6).should be_within(0.000001).of t
      $time_range.end.to_f.round(6).should be_within(0.000001).of t + 1.5
      $time_range.exclude_end?.should be true

      DB[:que_jobs].get(:run_at).to_f.round(6).should be_within(0.000001).of(t + 3.0)
      args = JSON.parse(DB[:que_jobs].get(:args)).first
      args.keys.should == ['arg', 'start_at', 'end_at']
      args['arg'].should == 4
      args['start_at'].should be_within(0.000001).of(t + 1.5)
      args['end_at'].should be_within(0.000001).of(t + 3.0)
    ensure
      $args       = nil
      $time_range = nil
    end
  end
end
