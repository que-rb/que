require 'sequel'
require 'que'

DB = Sequel.connect "postgres://postgres:@localhost/que"

DB.drop_table? :jobs
DB.run <<-SQL
  CREATE TABLE jobs
  (
    priority integer NOT NULL,
    run_at timestamp with time zone NOT NULL DEFAULT now(),
    job_id bigserial NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    type text NOT NULL,
    args json NOT NULL DEFAULT '[]'::json,
    data json NOT NULL DEFAULT '{}'::json,
    CONSTRAINT jobs_pkey PRIMARY KEY (priority, run_at, job_id),
    CONSTRAINT valid_priority CHECK (priority >= 1 AND priority <= 5)
  );
SQL

RSpec.configure do |config|
  config.before do
    Que::Worker.state = :off
    DB[:jobs].delete
  end
end

Que::Worker.state = :async # Boot up.

# For use when debugging specs:
# require 'logger'
# Que.logger = Logger.new(STDOUT)
# DB.loggers << Logger.new(STDOUT)
