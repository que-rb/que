### Unreleased

* Use multi_json so we always use the fastest JSON parser available. (BukhariH)
* :sync mode now ignores scheduled jobs (jobs queued with a specific run_at).

### 0.1.0 (2013-11-18)

* Initial public release, after a test-driven rewrite. Officially support Ruby 2.0.0 and Postgres 9.2+. Also support ActiveRecord and bare PG::Connections, in or out of a ConnectionPool. Added a Railtie for easier setup with Rails, as well as a migration generator.

### 0.0.1 (2013-11-07)

* Copy-pasted from an app of mine. Very Sequel-specific. Nobody look at it, let's pretend it never happened.
