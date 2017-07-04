# frozen_string_literal: true

require 'forwardable'
require 'socket' # For Socket.gethostname
require 'json'

module Que
  CURRENT_HOSTNAME = Socket.gethostname.freeze
  DEFAULT_QUEUE    = 'default'.freeze

  class Error < StandardError; end

  require_relative 'que/utils/assertions'
  require_relative 'que/utils/introspection'
  require_relative 'que/utils/json_serialization'
  require_relative 'que/utils/logging'
  require_relative 'que/utils/queue_management'
  require_relative 'que/utils/transactions'

  require_relative 'que/config'
  require_relative 'que/connection_pool'
  require_relative 'que/job'
  require_relative 'que/job_queue'
  require_relative 'que/listener'
  require_relative 'que/locker'
  require_relative 'que/migrations'
  require_relative 'que/poller'
  require_relative 'que/result_queue'
  require_relative 'que/sql'
  require_relative 'que/version'
  require_relative 'que/worker'

  class << self
    include Utils::Assertions
    include Utils::Introspection
    include Utils::JSONSerialization
    include Utils::Logging
    include Utils::QueueManagement
    include Utils::Transactions

    extend Forwardable

    # Copy some commonly-used methods here, for convenience.
    def_delegators :pool, :execute, :checkout, :in_transaction?
    def_delegators Job, :enqueue, :run_synchronously, :run_synchronously=
    def_delegators Migrations, :db_version, :migrate!
  end
end
