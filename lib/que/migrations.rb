# frozen_string_literal: true

module Que
  module Migrations
    # In order to ship a schema change, add the relevant up and down sql files
    # to the migrations directory, and bump the version here.
    CURRENT_VERSION = 8

    class << self
      def migrate!(version:)
        Que.transaction do
          current = db_version

          if current == version
            return
          elsif current < version
            direction = :up
            steps = ((current + 1)..version).to_a
          elsif current > version
            direction = :down
            steps = ((version + 1)..current).to_a.reverse
          end

          steps.each do |step|
            filename = [
              File.dirname(__FILE__),
              'migrations',
              step,
              direction,
            ].join('/') << '.sql'
            Que.execute(File.read(filename))
          end

          set_db_version(version)
        end
      end

      def db_version
        result =
          Que.execute <<-SQL
            SELECT relname, description
            FROM pg_class
            LEFT JOIN pg_description ON pg_description.objoid = pg_class.oid
            WHERE relname = 'que_jobs'
          SQL

        if result.none?
          # No table in the database at all.
          0
        elsif (d = result.first[:description]).nil?
          # The table exists but the version comment is missing
          _raise_db_version_comment_missing_error
        else
          d.to_i
        end
      end

      # The que_jobs table could be missing the schema version comment either due to:
      # - Being created before the migration system existed; or
      # - A bug in Rails schema dump in some versions of Rails
      # The former is the case on Que versions prior to v0.5.0 (2014-01-14). Upgrading directly from there is unsupported, so we just raise in all cases of the comment being missing
      def _raise_db_version_comment_missing_error
        raise Error, <<~ERROR
          Cannot determine Que DB schema version.

          The que_jobs table is missing its comment recording the Que DB schema version. This is likely due to a bug in Rails schema dump in Rails 7 versions prior to 7.0.3, omitting comments - see https://github.com/que-rb/que/issues/363. Please determine the appropriate schema version from your migrations and record it manually by running the following SQL (replacing version as appropriate):

          COMMENT ON TABLE que_jobs IS 'version';
        ERROR
      end

      def set_db_version(version)
        i = version.to_i
        Que.execute "COMMENT ON TABLE que_jobs IS '#{i}'" unless i.zero?
      end
    end
  end
end
