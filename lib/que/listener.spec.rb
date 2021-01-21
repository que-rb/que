# frozen_string_literal: true

require 'spec_helper'

describe Que::Listener do
  attr_reader :connection

  let :listener do
    Que::Listener.new(connection: connection)
  end

  let :message_1 do
    {
      queue: 'queue_name',
      priority: 90,
      run_at: "2017-06-30T18:33:33.402669Z",
      id: 44,
    }
  end

  let :message_2 do
    {
      queue: 'queue_name',
      priority: 90,
      run_at: "2017-06-30T18:33:35.425307Z",
      id: 46,
    }
  end

  before do
    # Add a couple more message formats, for testing purposes only.
    Que::Listener::MESSAGE_FORMATS[:type_1] = {value: Integer}
    Que::Listener::MESSAGE_FORMATS[:type_2] = {value: Integer}
  end

  after do
    # Clean out testing formats.
    objects = Que::Listener::MESSAGE_FORMATS
    assert_instance_of Hash, objects.delete(:type_1)
    assert_instance_of Hash, objects.delete(:type_2)
  end

  around do |&block|
    super() do
      DEFAULT_QUE_POOL.checkout do |conn|
        begin
          @connection = conn
          listener.listen

          block.call
        ensure
          listener.unlisten
        end
      end
    end
  end

  def notify(payload, channel: "que_listener_#{connection.backend_pid}")
    payload = JSON.dump(payload) unless payload.is_a?(String)
    DB.notify(channel, payload: payload)
  end

  def notify_multiple(notifications)
    # Avoid race conditions by making sure that all notifications are visible at
    # the same time:
    DB.transaction { notifications.each { |n| notify(n) } }
  end

  describe "wait_for_grouped_messages" do
    it "should return empty if there were no messages before the timeout" do
      # Use a short timeout, since we'll always hit it in this spec.
      assert_equal({}, listener.wait_for_grouped_messages(0.001))
      assert_empty internal_messages(event: 'listener_filtered_messages')
    end

    it "should return frozen messages" do
      notify(message_type: 'type_1', value: 4)

      result = listener.wait_for_grouped_messages(10)[:type_1].first
      assert_equal({value: 4}, result)
      assert result.frozen?

      assert_equal(
        [
          {
            internal_event: 'listener_filtered_messages',
            object_id: listener.object_id,
            backend_pid: connection.backend_pid,
            channel: "que_listener_#{connection.backend_pid}",
            messages: [{message_type: 'type_1', value: 4}],
          }
        ],
        internal_messages(event: 'listener_filtered_messages')
      )
    end

    it "should return messages to the locker in bulk by type" do
      notifications = []

      5.times do |i|
        notifications.push(message_type: 'type_1', value: i)
        notifications.push(message_type: 'type_2', value: i)
      end

      notify_multiple(notifications)

      assert_equal(
        {
          type_1: 5.times.map{|i| {value: i}},
          type_2: 5.times.map{|i| {value: i}},
        },
        listener.wait_for_grouped_messages(10),
      )
    end

    it "should not return a message type entry if none of the messages were well-formed" do
      q = Queue.new
      Que.error_notifier = proc { |e| q.push(e) }

      notify({ message_type: 'job_available', priority: 2, id: 4 })
      assert_equal({}, listener.wait_for_grouped_messages(10))

      error = q.pop
      assert_instance_of Que::Error, error
      assert_match(/doesn't match format!/, error.message)
    end

    it "should accept arrays of messages" do
      notifications = []

      [0, 5].each do |i|
        notifications << (1..5).map{|j| {message_type: 'type_1', value: i + j}}
        notifications << (1..5).map{|j| {message_type: 'type_2', value: i + j}}
      end

      notify_multiple(notifications)

      assert_equal(
        {
          type_1: (1..10).map{|i| {value: i}},
          type_2: (1..10).map{|i| {value: i}},
        },
        listener.wait_for_grouped_messages(10),
      )
    end

    describe "when given a specific channel" do
      let :listener do
        Que::Listener.new(connection: connection, channel: 'test_channel')
      end

      it "should listen on that channel" do
        notify({message_type: 'type_1', value: 4}, channel: 'test_channel')

        result = listener.wait_for_grouped_messages(10)[:type_1].first
        assert_equal({value: 4}, result)
      end
    end

    describe "when the messages aren't valid JSON of the format we expect" do
      let(:notified_errors) { [] }

      before do
        Que.error_notifier = proc { |e| notified_errors << e }
      end

      def assert_ignored_notification(payload)
        notify payload
        assert_equal({}, listener.wait_for_grouped_messages(10))
      end

      it "should be resilient to messages that aren't valid JSON" do
        assert_ignored_notification "nil"
        assert_ignored_notification 'blah'
        assert_ignored_notification '{"blah:"}'

        sleep_until_equal(3) { notified_errors.count }
        notified_errors.each{|e| assert_instance_of(JSON::ParserError, e)}
      end

      it "should be resilient to JSON messages with unexpected structures" do
        assert_ignored_notification message_type: 6
        assert_ignored_notification arg: 'blah'
        assert_ignored_notification [nil]
      end
    end
  end

  describe "unlisten" do
    it "should stop listening for new messages" do
      notify(message_type: 'type_1')
      connection.drain_notifications

      listener.unlisten
      notify(message_type: 'type_1')

      # Execute a new query to fetch any new notifications.
      connection.execute "SELECT 1"
      assert_nil connection.next_notification
    end

    it "when unlistening should not leave any residual messages" do
      5.times { notify(message_type: 'type_1') }

      listener.unlisten
      assert_nil connection.next_notification

      # Execute a new query to fetch any remaining notifications.
      connection.execute "SELECT 1"
      assert_nil connection.next_notification
    end
  end

  describe "message processing" do
    describe "when the message is malformed" do
      let :message_to_malform do
        {
          queue: 'queue_name',
          priority: 90,
          run_at: "2017-06-30T18:33:35.425307Z",
          id: 45,
        }
      end

      let :all_messages do
        [
          message_1,
          message_to_malform,
          message_2,
        ]
      end

      def assert_message_ignored
        DB.transaction do
          all_messages.each { |m| notify(m.merge(message_type: 'job_available')) }
        end

        assert_equal(
          {
            job_available: [
              message_1,
              message_2,
            ]
          },
          listener.wait_for_grouped_messages(10),
        )
      end

      # Avoid spec noise:
      before { Que.error_notifier = nil }

      it "should ignore it if a field is the wrong type" do
        message_to_malform[:id] = message_to_malform[:id].to_s
        assert_message_ignored
      end

      it "should ignore it if a field is missing" do
        message_to_malform.delete(:id)
        assert_message_ignored
      end

      it "should ignore it if an extra field is present" do
        message_to_malform[:extra] = 'blah'
        assert_message_ignored
      end

      it "should asynchronously report messages that don't match the format" do
        message_to_malform.delete(:id)
        error = nil
        Que.error_notifier = proc { |e| error = e }
        assert_message_ignored
        sleep_until { !error.nil? }

        assert_instance_of Que::Error, error

        expected_message = [
          "Message of type 'job_available' doesn't match format!",
          "Message: {:priority=>90, :queue=>\"queue_name\", :run_at=>\"2017-06-30T18:33:35.425307Z\"}",
          "Format: {:id=>Integer, :priority=>Integer, :queue=>String, :run_at=>/\\A\\d{4}\\-\\d{2}\\-\\d{2}T\\d{2}:\\d{2}:\\d{2}.\\d{6}Z\\z/}",
        ].join("\n")

        assert_equal expected_message, error.message
      end
    end
  end
end
