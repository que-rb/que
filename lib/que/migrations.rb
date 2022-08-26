# frozen_string_literal: true

module Que
  module Migrations
    # In order to ship a schema change, add the relevant up and down sql files
    # to the migrations directory, and bump the version here.
    CURRENT_VERSION = 7

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
          if _db_schema_matches_db_version_1?
            1
          else
            _raise_db_version_comment_missing_error
          end
        else
          d.to_i
        end
      end

      # The que_jobs table could be missing the schema version comment either due to:
      # - Being created before the migration system existed (matching DB version 1); or
      # - A bug in Rails schema dump in some versions of Rails
      # So to determine which is the case, here we check an aspect of the schema that's only like that if just the first migration has been applied
      def _db_schema_matches_db_version_1?
        result =
          Que.execute <<-SQL
            SELECT column_default AS default_priority
            FROM information_schema.columns
            WHERE (table_schema, table_name, column_name) = ('public', 'que_jobs', 'priority');
          SQL
        result.first[:default_priority] == '1'
      end

      def _raise_db_version_comment_missing_error
        raise Error, <<~ERROR
          Cannot determine Que DB schema version.

          The que_jobs table is abnormally missing its comment recording the Que DB schema version. This is likely due to a bug in Rails schema dump in Rails 7 versions prior to 7.0.3, omitting comments - see https://github.com/que-rb/que/issues/377. Please determine the appropriate schema version from your migrations and record it manually by running the following SQL (replacing version as appropriate):

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
