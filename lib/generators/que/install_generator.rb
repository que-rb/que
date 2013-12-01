require 'rails/generators'
require 'rails/generators/migration'
require 'active_record'

module Que
  class InstallGenerator < Rails::Generators::Base
    include Rails::Generators::Migration

    namespace 'que:install'
    self.source_paths << File.join(File.dirname(__FILE__), 'templates')
    desc "Generates a migration to add Que's job table."

    def self.next_migration_number(dirname)
      next_migration_number = current_migration_number(dirname) + 1
      ActiveRecord::Migration.next_migration_number(next_migration_number)
    end

    def create_migration_file
      migration_template 'add_que.rb', 'db/migrate/add_que.rb'
    end
  end
end
